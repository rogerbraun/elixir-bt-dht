require Bitwise
defmodule BtDht.Nodes do
  def add_node(nodes, {id, _ip, _port} = info) do
    List.keystore nodes, id, 0, info
  end

  def add_wire_node(nodes, wire_node) do
    add_node(nodes, from_wire(wire_node))
  end

  def add_wire_nodes(nodes, << >>), do: nodes

  def add_wire_nodes(nodes, << wire_node::binary-26, rest::binary >>) do
    nodes = add_wire_node(nodes, wire_node)
    add_wire_nodes(nodes,rest)
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

  def from_wire(<< id::binary-20, a::integer-8, b::integer-8, c::integer-8, d::integer-8, port::integer-16 >>) do
    {id, {a, b, c, d}, port}
  end

  def to_wire({id, {a, b, c, d}, port}) do
    << id::binary-20, a::integer-8, b::integer-8, c::integer-8, d::integer-8, port::integer-16 >>
  end

  def to_wire([]) do
    << >>
  end

  def to_wire([node | rest]) do
    to_wire(node) <> to_wire(rest)
  end
end
