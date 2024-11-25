// Based on https://www.semanticscholar.org/paper/A-System-for-Efficient-and-Flexible-One-Way-in-C%2B%2B-Hudson/9609985dbef43633f4deb88c949a9776e0cd766b
// https://repository.gatech.edu/server/api/core/bitstreams/3117139f-5de2-4f1f-9662-8723bae97a6d/content

final class AttributeGraph {
    var nodes: [AnyNode] = []
    var currentNode: AnyNode?

    func input<A>(name: String, _ value: A) -> Node<A> {
        let n = Node(name: name, in: self, wrappedValue: value)
        nodes.append(n)
        return n
    }

    func rule<A>(name: String, _ rule: @escaping () -> A) -> Node<A> {
        let n = Node(name: name, in: self, rule: rule)
        nodes.append(n)
        return n
    }

    func graphViz() -> String {
        let nodesStr = nodes.map {
            "\($0.name)\($0.potentiallyDirty ? " [style=dashed]" : "")"
        }.joined(separator: "\n")
        let edges = nodes.flatMap(\.outgoingEdges).map {
            "\($0.from.name) -> \($0.to.name)\($0.pending ? " [style=dashed]" : "")"
        }.joined(separator: "\n")
        return """
        digraph {
        \(nodesStr)
        \(edges)
        }
        """
    }
}

protocol AnyNode: AnyObject {
    var name: String { get }
    var outgoingEdges: [Edge] { get set }
    var incomingEdges: [Edge] { get set }
    var potentiallyDirty: Bool { get set }

    func recomputeIfNeeded()
}

final class Edge {
    unowned var from: AnyNode
    unowned var to: AnyNode
    var pending = false

    init(from: AnyNode, to: AnyNode) {
        self.from = from
        self.to = to
    }
}

final class Node<A>: AnyNode {
    unowned var graph: AttributeGraph
    var name: String
    var rule: (() -> A)?
    var incomingEdges: [Edge] = []
    var outgoingEdges: [Edge] = []
    var potentiallyDirty: Bool = false {
        didSet {
            guard potentiallyDirty, potentiallyDirty != oldValue else { return }
            for e in outgoingEdges {
                e.to.potentiallyDirty = true
            }
        }
    }

    private var _cachedValue: A?

    var wrappedValue: A {
        get {
            recomputeIfNeeded()
            return _cachedValue!
        }
        set {
            assert(rule == nil)
            _cachedValue = newValue
            for e in outgoingEdges {
                e.pending = true
                e.to.potentiallyDirty = true
            }
        }
    }

    func recomputeIfNeeded() {
        // record dependency
        if let c = graph.currentNode {
            let edge = Edge(from: self, to: c)
            outgoingEdges.append(edge)
            c.incomingEdges.append(edge)
        }

        guard let rule else { return }

        if !potentiallyDirty && _cachedValue != nil { return }

        for edge in incomingEdges {
            edge.from.recomputeIfNeeded()
        }

        let hasPendingIncomingEdge = incomingEdges.contains(where: \.pending)
        potentiallyDirty = false

        if hasPendingIncomingEdge || _cachedValue == nil {
            let previousNode = graph.currentNode
            defer { graph.currentNode = previousNode }
            graph.currentNode = self
            let isInitial = _cachedValue == nil
            removeIncomingEdges()
            _cachedValue = rule()
            // TODO only if _cachedValue has changed
            if !isInitial {
                for o in outgoingEdges {
                    o.pending = true
                }
            }
        }
    }

    func removeIncomingEdges() {
        for e in incomingEdges {
            e.from.outgoingEdges.removeAll(where: { $0 === e })
        }
        incomingEdges = []
    }

    init(name: String, in graph: AttributeGraph, wrappedValue: A) {
        self.name = name
        self.graph = graph
        self._cachedValue = wrappedValue
    }

    init(name: String, in graph: AttributeGraph, rule: @escaping () -> A) {
        self.name = name
        self.graph = graph
        self.rule = rule
    }
}
