defmodule BtDht do
  use GenServer

  def start(port \\ 0) do
    initial_state = %{
      id: :crypto.rand_bytes(20),
      token: :crypto.rand_bytes(4),
      nodes: [],
      peers: %{}
    }

    {:ok, pid} = GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
    GenServer.cast(pid, {:open_socket, port})
  end

  def bootstrap(ip \\ 'routes.bittorrent.com', port \\ 6881) do
    GenServer.cast(__MODULE__, {:bootstrap, ip, port})
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:open_socket, port}, state) do
    {:ok, socket} = :gen_udp.open(port, [:binary])
    state = Dict.put(state, :socket, socket)
    {:noreply, state}
  end

  def handle_cast({:bootstrap, ip, port}, %{token: token, id: id, socket: socket, nodes: []} = state) do
    BtDht.RPC.find_node socket, ip, port, token, id, id
    {:noreply, state}
  end

  def handle_cast({:bootstrap, _ip, _port}, %{token: token, id: id, socket: socket, nodes: nodes } = state) do
    close_nodes = BtDht.Nodes.neighbour_nodes(nodes, id)
    Enum.each(close_nodes, fn({_, ip, port}) ->
      BtDht.RPC.find_node socket, ip, port, token, id, id
    end)
    {:noreply, state}
  end

  def handle_info({:udp, _socket, ip, port, data}, state) do
    state = case Bencode.decode(data) do
      {:ok, decoded_message} ->
        BtDht.RPC.handle_message_and_check_sender(state, decoded_message, {ip, port})
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

  def answer_find_node(token, id, neighbour_nodes) do
    %{
      t: token,
      y: "r",
      r: %{
        id: id,
        nodes: BtDht.Nodes.to_wire(neighbour_nodes)
      }
    }
    |> Bencode.encode!
  end

  def answer_get_peers(token, id, neighbour_nodes) do
    %{
      t: token,
      y: "r",
      r: %{
        id: id,
        nodes: BtDht.Nodes.to_wire(neighbour_nodes),
        token: :crypto.rand_bytes(4)
      }
    }
    |> Bencode.encode!
  end

  def answer_get_peers_with_peers(token, id, values) do
    values = Enum.map(values, fn({{a, b, c, d}, port}) -> << a, b, c, d, port::integer-16 >> end)

    %{
      t: token,
      y: "r",
      r: %{
        id: id,
        values: values,
        token: :crypto.rand_bytes(4)
      }
    }
    |> Bencode.encode!
  end

  def answer_ping(token, id) do
    %{
      t: token,
      y: "r",
      r: %{
        id: id,
      }
    }
    |> Bencode.encode!
  end
end

defmodule BtDht.RPC do

  def handle_message_and_check_sender(%{nodes: nodes} = state, %{"a" => %{"id" => id} }= message, {ip, port} = sender) do
    handle_message_and_check_sender(state, message, sender, id)
  end

  def handle_message_and_check_sender(%{nodes: nodes} = state, %{"r" => %{"id" => id} }= message, {ip, port} = sender) do
    handle_message_and_check_sender(state, message, sender, id)
  end

  def handle_message_and_check_sender(%{nodes: nodes} = state, message, {ip, port} = sender, id \\ false) do
    if id do
      nodes = BtDht.Nodes.add_node(nodes, {id, ip, port})
      state = %{state | nodes: nodes }
    end
    handle_message(state, message, sender)
  end

  def handle_message(%{nodes: nodes, id: id} = state, %{"r" => %{ "nodes" => wire_nodes } }, _sender) do
    IO.puts "Received some nodes..."
    nodes = BtDht.Nodes.add_wire_nodes(nodes, wire_nodes)
    [ closest_node ] = BtDht.Nodes.neighbour_nodes(nodes, id, 1)
    IO.puts "Closest node:"
    IO.inspect closest_node
    IO.puts BtDht.Nodes.node_distance(id, elem(closest_node, 0))
    %{ state | nodes: nodes }
  end

  def handle_message(%{nodes: nodes, socket: socket, id: id} = state, %{"q" => "find_node", "t" => token, "a" => %{ "target" => target}}, sender ) do
    IO.puts "Received find_node"
    answer_find_node(socket, sender, id, token, target, nodes)
    state
  end

  def handle_message(%{nodes: nodes, socket: socket, id: id, peers: peers} = state, %{"q" => "get_peers", "t" => token, "a" => %{ "info_hash" => target}}, sender ) do
    IO.puts "Received get_peers"
    answer_get_peers(socket, sender, id, token, target, nodes, peers)
    state
  end

  def handle_message(%{socket: socket, id: id} = state, %{"t" => token, "q" => "ping", "a" => %{ "id" => other_id} }, sender ) do
    IO.puts "Received Ping..."
    answer_ping(socket, sender, id, token)
    state
  end

  def handle_message(%{socket: socket, id: id} = state, %{"q" => "vote"}, sender ) do
    IO.puts "Received Vote, ignoring..."
    state
  end

  def handle_message(%{socket: socket, id: id, peers: peers} = state, %{"t" => token, "q" => "announce_peer", "a" => %{"info_hash" => info_hash, "port" => peer_port} } = message , {ip, port} = sender) do
    if message["a"]["implied_port"] == 1 do
      peer = sender
    else
      peer = {ip,  peer_port}
    end

    IO.puts "Received announce_peer"
    IO.inspect message
    if peers[info_hash] do
      peers = Dict.put(peers, info_hash, [peer | peers[info_hash]])
    else
      peers = Dict.put(peers, info_hash, [peer])
    end

    answer_ping(socket, sender, id, token)

    %{ state | peers: peers }
  end

  def handle_message(state, message, _sender) do
    IO.inspect message
    state
  end

  def answer_ping(socket, {ip, port}, id, token) do
    message = BtDht.Messages.answer_ping(token, id)
    :gen_udp.send(socket, ip, port, message)
  end

  def answer_find_node(socket, {ip, port}, id, token, target, nodes) do
    neighbour_nodes = BtDht.Nodes.neighbour_nodes(nodes, target)
    message = BtDht.Messages.answer_find_node(token, id, neighbour_nodes)
    :gen_udp.send(socket, ip, port, message)
  end

  def answer_get_peers(socket, {ip, port}, id, token, target, nodes, peers) do
    if peers[target] do
      values = peers[target]
      message = BtDht.Messages.answer_get_peers_with_peers(token, id, values)
    else
      neighbour_nodes = BtDht.Nodes.neighbour_nodes(nodes, target)
      message = BtDht.Messages.answer_get_peers(token, id, neighbour_nodes)
    end
    :gen_udp.send(socket, ip, port, message)
  end

  def find_node(socket, ip, port, token, id, target) do
    message = BtDht.Messages.find_node(token, id, target)
    :gen_udp.send(socket, ip, port, message)
  end
end
