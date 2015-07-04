defmodule BtDht do
  use GenServer

  def start(port \\ 0) do
    initial_state = %{
      id: :crypto.rand_bytes(20),
      token: :crypto.rand_bytes(4),
      nodes: []
    }

    {:ok, pid} = GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
    GenServer.cast(pid, {:open_socket, port})
  end

  def bootstrap do
    GenServer.cast(__MODULE__, {:bootstrap, 'router.bittorrent.com', 6881})
  end

  def handle_cast({:open_socket, port}, state) do
    {:ok, socket} = :gen_udp.open(port, [:binary])
    state = Dict.put(state, :socket, socket)
    {:noreply, state}
  end

  def handle_cast({:bootstrap, ip, port}, %{token: token, id: id, socket: socket} = state) do
    BtDht.RPC.find_node socket, ip, port, token, id, id
    {:noreply, state}
  end

  def handle_info({:udp, socket, ip, port, data}, state) do
    state = case Bencode.decode(data) do
      {:ok, decoded_message} ->
        BtDht.RPC.handle_message(state, decoded_message, {ip, port})
      {_, error} ->
        IO.inspect(error); state
    end

    {:noreply, state}
  end

  def handle_info(msg, state) do
    IO.inspect(msg)
    {:noreply, state}
  end
end

require Bitwise
defmodule BtDht.Nodes do
  def add_node(nodes, {id, _ip, _port} = info) do
    List.keystore nodes, id, 0, info
  end

  def add_wire_node(nodes, << id::binary-20, a::integer-8, b::integer-8, c::integer-8, d::integer-8, port::integer-16 >>) do
    add_node(nodes, {id, {a, b, c, d}, port})
  end

  def node_distance(node, other_node) do
    << node_as_integer::integer-160 >> = node
    << other_node_as_integer::integer-160 >> = other_node

    Bitwise.bxor(node_as_integer, other_node_as_integer)
  end

  def neighbour_nodes(nodes, reference, amount \\ 8) do
    mapper = fn({node, _, _}) -> node_distance(reference, node) end
    nodes
    |> Enum.sort_by(mapper, &<=/2)
    |> Enum.take(amount)
  end
end

defmodule BtDht.Messages do
  def find_node(token, id, target) do
    %{
      t: token,
      y: "q",
      q: "find_node",
      a: %{
        id: id,
        target: target
      }
    }
    |> Bencode.encode!
  end

  def answer_find_node(token, id, target, neighbour_nodes) do
    %{
      t: token,
      y: "r",
      r: %{
        id: id,
        nodes: neighbour_nodes
      }
    }

  end
end

defmodule BtDht.RPC do
  def handle_message(%{nodes: nodes} = state, %{"r" => %{ "nodes" => wire_nodes } }, _sender) do
    IO.puts "Received some nodes..."
    nodes = BtDht.Nodes.add_wire_nodes(nodes, wire_nodes)
    state
  end

  def handle_message(%{nodes: nodes, socket: socket, id: id, token: token} = state, %{"q" => "find_node", "t" => token, "a" => %{ "target" => target}}, sender ) do
    IO.puts "Received find_node"
    answer_find_node(socket, sender, id, token, target, nodes)
    state
  end

  def handle_message(state, message, sender) do
    IO.inspect message
    state
  end

  def answer_find_node(socket, {ip, port}, id, token, target, nodes) do
    neighbour_nodes = BtDht.Nodes.neighbour_nodes(nodes, target)
    message = BtDht.Messages.answer_find_node(token, id, target, neighbour_nodes)
    :gen_udp,send(socket, ip, port, message)
  end

  def find_node(socket, ip, port, token, id, target) do
    message = BtDht.Messages.find_node(token, id, target)
    :gen_udp.send(socket, ip, port, message)
  end
end
