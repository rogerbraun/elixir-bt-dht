defmodule BtDhtTest do
  use ExUnit.Case

  test "the truth" do
    assert 1 + 1 == 2
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
end
