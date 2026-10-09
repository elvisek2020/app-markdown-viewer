import cmark_gfm

typealias CMarkNode = UnsafeMutablePointer<cmark_node>

/// Tenká vrstva nad C API cmarku, aby se AST transformace četly jako Swift.
extension UnsafeMutablePointer where Pointee == cmark_node {
    var type: cmark_node_type { cmark_node_get_type(self) }
    var firstChild: CMarkNode? { cmark_node_first_child(self) }
    var next: CMarkNode? { cmark_node_next(self) }
    var parent: CMarkNode? { cmark_node_parent(self) }

    var literal: String? {
        guard let cString = cmark_node_get_literal(self) else { return nil }
        return String(cString: cString)
    }

    var fenceInfo: String {
        guard let cString = cmark_node_get_fence_info(self) else { return "" }
        return String(cString: cString)
    }

    var headingLevel: Int { Int(cmark_node_get_heading_level(self)) }
    var startLine: Int { Int(cmark_node_get_start_line(self)) }
    var startColumn: Int { Int(cmark_node_get_start_column(self)) }
    var endLine: Int { Int(cmark_node_get_end_line(self)) }
    var endColumn: Int { Int(cmark_node_get_end_column(self)) }

    /// Hodnota atributu `data-sourcepos`, jak ji generuje cmark (`řádek:sloupec-řádek:sloupec`).
    var sourcepos: String { "\(startLine):\(startColumn)-\(endLine):\(endColumn)" }

    var children: [CMarkNode] {
        var result: [CMarkNode] = []
        var child = firstChild
        while let node = child {
            result.append(node)
            child = node.next
        }
        return result
    }

    /// Všechny potomky v pořadí dokumentu (pre-order), bez uzlu samotného.
    var descendants: [CMarkNode] {
        var result: [CMarkNode] = []
        var stack = children.reversed() as [CMarkNode]
        while let node = stack.popLast() {
            result.append(node)
            stack.append(contentsOf: node.children.reversed())
        }
        return result
    }
}

/// Vytvoří custom block, jehož HTML tvoří jen `onEnter` a `onExit` (bez escapování).
func makeCustomBlock(onEnter: String, onExit: String) -> CMarkNode {
    let node = cmark_node_new(CMARK_NODE_CUSTOM_BLOCK)!
    cmark_node_set_on_enter(node, onEnter)
    cmark_node_set_on_exit(node, onExit)
    return node
}

func makeCustomInline(onEnter: String, onExit: String) -> CMarkNode {
    let node = cmark_node_new(CMARK_NODE_CUSTOM_INLINE)!
    cmark_node_set_on_enter(node, onEnter)
    cmark_node_set_on_exit(node, onExit)
    return node
}
