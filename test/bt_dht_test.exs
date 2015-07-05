defmodule BtDhtTest do
  use ExUnit.Case

  setup do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    on_exit fn ->
      :gen_udp.close(socket)
    end

    id = :crypto.rand_bytes(20)
    token = :crypto.rand_bytes(4)

    state = %{
      id: id,
      socket: socket,
      peers: %{},
      nodes: [],
      token: token
    }

    {:ok, state: state}
  end

  test "BtDht.Nodes.add_node" do
    assert BtDht.Nodes.add_node([], {:a, :b, :c}) == [{:a, :b, :c}]
    assert BtDht.Nodes.add_node([{:a, 0, 0}], {:a, :b, :c}) == [{:a, :b, :c}]
  end

  test "BtDht.Nodes.node_distance" do
    node = << 0::integer-160 >>
    other_node = << 1::integer-160 >>

    assert BtDht.Nodes.node_distance(node, other_node) == 1
  end

  test "BtDht.Nodes.neighbour_nodes" do
    reference = << 0::integer-160 >>
    nodes = [
      { << 2::integer-160 >>, :ip, :port },
      { << 1::integer-160 >>, :ip, :port }
    ]

    assert BtDht.Nodes.neighbour_nodes(nodes, reference) == Enum.reverse(nodes)
    assert BtDht.Nodes.neighbour_nodes(nodes, reference, 1) == Enum.reverse(nodes) |> Enum.take(1)
  end

  test "BtDht.Nodes.add_wire_node" do
    wire_node = << 0::integer-160, 127, 0, 0, 1, 6881::integer-16 >>
    assert BtDht.Nodes.add_wire_node([], wire_node) == [{<< 0::integer-160>>, {127, 0, 0, 1}, 6881}]
  end

  test "BtDht.Nodes.from_wire" do
    wire_node = << 0::integer-160, 127, 0, 0, 1, 6881::integer-16 >>
    assert BtDht.Nodes.from_wire(wire_node) == {<< 0::integer-160>>, {127, 0, 0, 1}, 6881}
  end

  test "BtDht.Nodes.to_wire" do
    node = {<< 0::integer-160>>, {127, 0, 0, 1}, 6881}
    # Works for single nodes
    assert BtDht.Nodes.to_wire(node) == << 0::integer-160, 127, 0, 0, 1, 6881::integer-16 >>
    # Works for lists of nodes
    assert BtDht.Nodes.to_wire([node, node]) == << 0::integer-160, 127, 0, 0, 1, 6881::integer-16, 0::integer-160, 127, 0, 0, 1, 6881::integer-16 >>
  end

  test "BtDht.RPC - Handle announce_peer", context do
    ip = {127, 0, 0, 1}
    {:ok, port} = :inet.port(context.state.socket)
    info_hash = :crypto.rand_bytes(20)
    other_token = :crypto.rand_bytes(4)

    message = %{"t" => other_token, "y" => "q", "q" => "announce_peer", "a" =>  %{"id" => context.state.id, "implied_port" =>  1, "info_hash" => info_hash, "port" =>  6881, "token" =>  "aoeusnth"}}
    state = context.state
    sender = { ip, port }

    new_state = BtDht.RPC.handle_message(state, message, sender)
    assert new_state.peers[info_hash] == [{ip, port}]

    {:ok,{_ip, _port, recv_message} } = :gen_udp.recv(context.state.socket, 0, 2000)
    recv_message = Bencode.decode!(recv_message)

    assert recv_message == %{"r" => %{"id" => state.id} , "t" => other_token, "y" => "r"}

    # Without implied port
    message = %{"t" => other_token, "y" => "q", "q" => "announce_peer", "a" =>  %{"id" => context.state.id, "info_hash" => info_hash, "port" =>  6881, "token" =>  "aoeusnth"}}

    new_state = BtDht.RPC.handle_message(state, message, sender)
    assert new_state.peers[info_hash] == [{ip, 6881}]

    {:ok,{_ip, _port, recv_message} } = :gen_udp.recv(context.state.socket, 0, 2000)
    recv_message = Bencode.decode!(recv_message)

    assert recv_message == %{"r" => %{"id" => state.id} , "t" => other_token, "y" => "r"}
  end


  test "BtDht.RPC - Handle get_peers", context do
    ip = {127, 0, 0, 1}
    {:ok, port} = :inet.port(context.state.socket)
    info_hash = :crypto.rand_bytes(20)

    message = %{"t" => "aa", "y" => "q", "q" => "get_peers", "a" =>  %{"id" => context.state.id, "info_hash" => info_hash} }

    # When we don't have peer info
    nodes = [{<< 0::integer-160 >>, ip, port} ]

    state = %{ context.state | nodes: nodes }

    BtDht.RPC.handle_message(state, message, {ip, port})

    {:ok,{_ip, _port, recv_message} } = :gen_udp.recv(context.state.socket, 0)

    recv_message = Bencode.decode!(recv_message)

    assert recv_message["y"] == "r"
    assert recv_message["r"]["id"] == context.state.id
    assert recv_message["r"]["nodes"] == << 0::integer-160, 127, 0, 0, 1, port::integer-16 >>

    # When we DO have peer info

    peers = Dict.put(%{}, info_hash, [{ ip, port }] )
    state = %{ context.state | peers: peers }

    BtDht.RPC.handle_message(state, message, {ip, port})
    {:ok,{_ip, port, recv_message} } = :gen_udp.recv(context.state.socket, 0, 2000)
    recv_message = Bencode.decode!(recv_message)

    assert recv_message["y"] == "r"
    assert recv_message["r"]["id"] == context.state.id
    assert recv_message["r"]["values"] == [<< 127, 0, 0, 1, port::integer-16 >>]
  end

end
