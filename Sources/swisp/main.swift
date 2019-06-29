//
//  main.swift
//  Lisp
//
//  Created by John Naylor on 6/28/19.
//  Copyright © 2019 John Naylor. All rights reserved.
//

import Foundation

public enum SExpr {
    case Atom(String)
    case List([SExpr])
}

public var localContext = [String: (SExpr, [SExpr]?, [SExpr]?) -> SExpr]()
private var defaultEnvironment = [String: (SExpr, [SExpr]?, [SExpr]?) -> SExpr]()

extension SExpr {
    
    /**
     Evaluates this SExpression with the given functions environment
     
     - Parameter environment: A set of named functions of the default environment
     - Returns: the resulting SExpression after evaluation
     */
    public func eval(with locals: [SExpr]? = nil, for values: [SExpr]? = nil) -> SExpr? {
        var node = self
        
        switch node {
        case .Atom:
            return evaluateVariable(node, with: locals, for: values)
        case var .List(elements):
            var skip = false
            
            if elements.count > 1, case let .Atom(value) = elements[0] {
                skip = Builtins.mustSkip(value)
            }
            
            //Evaluate all subexpressions
            if !skip {
                elements = elements.map {
                    return $0.eval(with: locals, for: values)!
                }
            }
            
            node = .List(elements)
            
            // Obtains a reference to the function represented by the first atom and apply it, local definitions shadow global ones
            if elements.count > 0, case let .Atom(value) = elements[0], let f = localContext[value] ?? defaultEnvironment[value] {
                let r = f(node, locals, values)
                
                return r
            }
            
            return node
        }
    }
    
    private func evaluateVariable(_ v: SExpr, with locals: [SExpr]?, for values: [SExpr]?) -> SExpr {
        guard let locals = locals, let values = values else { return v }
        
        if locals.contains(v) {
            
            // The current atom is a variable, replace it with its value
            return values[locals.firstIndex(of: v)!]
        } else {
            // Not a variable, just return it
            return v
        }
    }
}

extension SExpr : Equatable {
    public static func ==(lhs: SExpr, rhs: SExpr) -> Bool {
        switch (lhs, rhs) {
        case let (.Atom(l), .Atom(r)):
            return l == r
        case let (.List(l), .List(r)):
            guard l.count == r.count else { return false }
            for (idx, el) in l.enumerated() {
                if el != r[idx] {
                    return false
                }
            }
            return true
        default:
            return false
        }
    }
}

extension SExpr : CustomStringConvertible {
    public var description: String {
        switch self {
        case let .Atom(value):
            return "\(value) "
        case let .List(subxexprs):
            var res = "("
            for expr in subxexprs {
                res += "\(expr) "
            }
            res += ")"
            
            return res
        }
    }
}

extension SExpr {
    
    /**
     Read LISP string and convert it to a hierarchicalS-Expresssion
     */
    public static func read(_ sexpr: String) -> SExpr {
        
        enum Token {
            case pOpen, pClose, textBlock(String)
        }
        
        /**
         Break down a string to a series of tokens
         
         - Parameter sexpr: Stringifed S-Expression
         - Returns: Series of tokens
         */
        func tokenize(_ sexpr: String) -> [Token] {
            var res = [Token]()
            var tmpText = ""
            
            for c in sexpr {
                switch c {
                case "(":
                    if tmpText != "" {
                        res.append(.textBlock(tmpText))
                        tmpText = ""
                    }
                    
                    res.append(.pOpen)
                    
                case ")":
                    if tmpText != "" {
                        res.append(.textBlock(tmpText))
                        tmpText = ""
                    }
                    
                    res.append(.pClose)
                    
                case " ":
                    if tmpText != "" {
                        res.append(.textBlock(tmpText))
                        tmpText = ""
                    }
                    
                default:
                    tmpText.append(c)
                }
            }
            
            return res
        }
        
        func appendTo(list: SExpr?, node: SExpr) -> SExpr {
            var list = list
            
            if list != nil, case var .List(elements) = list! {
                elements.append(node)
                list = .List(elements)
            } else {
                list = node
            }
            
            return list!
        }
        
        /**
         Parses a series of token to obtain a hierarchical S_Expression
         
         - Parameter tokens: Tokens to parse
         - Parameter node: Parent S-Expression if available
         
         - Returns: Tuple with remaining toens and resulting S-Expression
         */
        func parse(_ tokens: [Token], node: SExpr? = nil) -> (remaining: [Token], subexpr: SExpr?) {
            
            var tokens = tokens
            var node = node
            
            var i = 0
            
            repeat {
                let t = tokens[i]
                
                switch t {
                case .pOpen:
                    // new sexpr
                    let (tr, n) = parse(Array(tokens[(i+1)..<tokens.count]),
                                        node: .List([]))
                    assert(n != nil) // Cannot be nil
                    
                    (tokens, i) = (tr, 0)
                    node = appendTo(list: node, node: n!)
                    
                    if tokens.count != 0 {
                        continue
                    } else {
                        break
                    }
                case .pClose:
                    // close sexpr
                    return (Array(tokens[(i+1)..<tokens.count]), node)
                    
                case let .textBlock(value):
                    node = appendTo(list: node, node: .Atom(value))
                }
                
                i += 1
            } while (tokens.count > 0)
            
            return ([], node)
        }
        
        // Read: tokenize -> parse -> result
        let tokens = tokenize(sexpr)
        let res = parse(tokens)
        
        return res.subexpr ?? .List([])
    }
}

extension SExpr : ExpressibleByStringLiteral, ExpressibleByUnicodeScalarLiteral, ExpressibleByExtendedGraphemeClusterLiteral {
    
    public init(stringLiteral value: String) {
        self = SExpr.read(value)
    }
    
    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }
    
    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }
}

fileprivate enum Builtins:String {
    case quote, car, cdr, cons, equal, atom, cond, lambda, defun, list, println, eval
    
    /**
     True if the given parameter stop evaluation of sub-expressions
     Sub expression will be evaluated lazily by the operator
     
     - Parameter atom: Stringifed atom
     - Returns: True if the atom is the quote operator
     */
    public static func mustSkip(_ atom: String) -> Bool {
        return (atom == Builtins.quote.rawValue) ||
            (atom == Builtins.cond.rawValue) ||
            (atom == Builtins.defun.rawValue) ||
            (atom == Builtins.lambda.rawValue)
    }
}

// Local environment for locally defined functions
localContext = [String: (SExpr, [SExpr]?, [SExpr]?) -> SExpr]()

/// Global default builtin functions environment
///
/// Contains definitions for: quote, car, cdr, cons, equal, atom, cond, lambda, label, defun.
defaultEnvironment = {
    
    var env = [String: (SExpr, [SExpr]?, [SExpr]?) -> SExpr]()
    
    env[Builtins.quote.rawValue] = { params, locals, values in
        guard case let .List(parameters) = params, parameters.count == 2 else {
            return .List([])
        }
        
        return parameters[1]
    }
    
    env[Builtins.car.rawValue] = { params, locals, values in
        guard case let .List(parameters) = params, parameters.count == 2 else {
            return .List([])
        }
        guard case let .List(elements) = parameters[1], elements.count > 0 else {
            return .List([])
        }
        
        return elements.first!
    }
    
    env[Builtins.cdr.rawValue] = { params,locals,values in
        guard case let .List(parameters) = params, parameters.count == 2 else {
            return .List([])
        }
        
        guard case let .List(elements) = parameters[1], elements.count > 1 else {
            return .List([])
        }
        
        return .List(Array(elements.dropFirst(1)))
    }
    
    env[Builtins.cons.rawValue] = { params,locals,values in
        guard case let .List(parameters) = params, parameters.count == 3 else {
            return .List([])
        }
        
        guard case .List(let elRight) = parameters[2] else {
            return .List([])
        }
        
        switch parameters[1].eval(with: locals,for: values)! {
        case let .Atom(p):
            return .List([.Atom(p)]+elRight)
        default:
            return .List([])
        }
    }
    
    env[Builtins.equal.rawValue] = { params, locals, values in
        guard case let .List(elements) = params, elements.count == 3 else {
            return .List([])
        }
        
        let me = env[Builtins.equal.rawValue]!
        
        switch (elements[1].eval(with: locals, for: values)!,elements[2].eval(with: locals, for: values)!) {
        case (.Atom(let elLeft), .Atom(let elRight)):
            return elLeft == elRight ? .Atom("true") : .List([])
        case (.List(let elLeft), .List(let elRight)):
            guard elLeft.count == elRight.count else { return .List([])}
            for (idx, el) in elLeft.enumerated() {
                let testeq: [SExpr] = [.Atom("Equal"), el, elRight[idx]]
                if me(.List(testeq), locals, values) != SExpr.Atom("true") {
                    return .List([])
                }
            }
            
            return .Atom("true")
        default:
            return .List([])
        }
    }
    
    env[Builtins.atom.rawValue] = { params, locals, values in
        guard case let .List(parameters) = params, parameters.count == 2 else {
            return .List([])
        }
        
        switch parameters[1].eval(with: locals, for: values)! {
        case .Atom:
            return .Atom("true")
        default:
            return .List([])
        }
    }
    
    env[Builtins.cond.rawValue] = { params,locals,values in
        guard case let .List(parameters) = params, parameters.count > 1 else {
            return .List([])
        }
        
        for el in parameters.dropFirst(1) {
            guard case let .List(c) = el, c.count == 2 else {
                return .List([])
            }
            
            if c[0].eval(with: locals,for: values) != .List([]) {
                let res = c[1].eval(with: locals,for: values)
                
                return res!
            }
        }
        
        return .List([])
    }
    
    env[Builtins.defun.rawValue] =  { params,locals,values in
        guard case let .List(parameters) = params, parameters.count == 4 else {
            return .List([])
        }
        
        guard case let .Atom(lname) = parameters[1] else { return .List([]) }
        guard case let .List(vars) = parameters[2] else { return .List([]) }
        
        let lambda = parameters[3]
        
        let f: (SExpr, [SExpr]?, [SExpr]?)->SExpr = { params,locals,values in
            guard case var .List(p) = params else { return .List([]) }
            p = Array(p.dropFirst(1))
            
            // Replace parameters in the lambda with values
            if let result = lambda.eval(with: vars, for: p) {
                return result
            } else {
                return .List([])
            }
        }
        
        localContext[lname] = f
        
        return .List([])
    }
    
    env[Builtins.lambda.rawValue] = { params,locals,values in
        guard case let .List(parameters) = params, parameters.count == 3 else {
            return .List([])
        }
        
        guard case let .List(vars) = parameters[1] else { return .List([]) }
        let lambda = parameters[2]
        //Assign a name for this temporary closure
        let fname = "TMP$" + String(arc4random_uniform(UInt32.max))
        
        let f: (SExpr, [SExpr]?, [SExpr]?) -> SExpr = { params,locals,values in
            guard case var .List(p) = params else { return .List([]) }
            p = Array(p.dropFirst(1))
            
            //Remove temporary closure
            localContext[fname] = nil
            
            // Replace parameters in the lambda with values
            if let result = lambda.eval(with: vars, for: p) {
                return result
            } else {
                return .List([])
            }
        }
        
        localContext[fname] = f
        
        return .Atom(fname)
    }
    
    //List implemented as a classic builtin instead of a series of cons
    env[Builtins.list.rawValue] = { params,locals,values in
        guard case let .List(parameters) = params, parameters.count > 1 else {
            return .List([])
        }
        var res: [SExpr] = []
        
        for el in parameters.dropFirst(1) {
            switch el {
            case .Atom:
                res.append(el)
            case let .List(els):
                res.append(contentsOf: els)
            }
        }
        return .List(res)
    }
    
    env[Builtins.println.rawValue] = { params,locals,values in
        guard case let .List(parameters) = params, parameters.count > 1 else {
            return .List([])
        }
        
        print(parameters[1].eval(with: locals,for: values)!)
        return .List([])
    }
    
    env[Builtins.eval.rawValue] = { params,locals,values in
        guard case let .List(parameters) = params, parameters.count == 2 else {
            return .List([])
        }
        
        return parameters[1].eval(with: locals, for: values)!
    }
    
    return env
}()

var exit = false

while (!exit) {
    
    print(">>>", terminator: " ")
    
    let input = readLine(strippingNewline: true)
    
    exit = (input == "exit") ? true : false
    
    if !exit {
        let e = SExpr.read(input!)
        print(e.eval()!)
    }
}
