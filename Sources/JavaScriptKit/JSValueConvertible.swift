import _CJavaScriptKit

public protocol JSValueConvertible {
    func jsValue() -> JSValue
}

extension JSValue: JSValueConvertible {
    public func jsValue() -> JSValue { self }
}

extension Bool: JSValueConvertible {
    public func jsValue() -> JSValue { .boolean(self) }
}

extension Int: JSValueConvertible {
    public func jsValue() -> JSValue { .number(Int32(self)) }
}

extension String: JSValueConvertible {
    public func jsValue() -> JSValue { .string(self) }
}

extension JSObjectRef: JSValueConvertible {
    // `JSObjectRef.jsValue` is defined in JSObjectRef.swift to be able to overridden
    // from `JSFunctionRef`
}

private let Object = JSObjectRef.global.Object.function!

extension Dictionary where Value: JSValueConvertible, Key == String {
    public func jsValue() -> JSValue {
        Swift.Dictionary<Key, JSValueConvertible>.jsValue(self)()
    }
}

extension Dictionary: JSValueConvertible where Value == JSValueConvertible, Key == String {
    public func jsValue() -> JSValue {
        let object = Object.new()
        for (key, value) in self {
            object.set(key, value.jsValue())
        }
        return .object(object)
    }
}

private let Array = JSObjectRef.global.Array.function!

extension Array where Element: JSValueConvertible {
    public func jsValue() -> JSValue {
        Swift.Array<JSValueConvertible>.jsValue(self)()
    }
}

extension Array: JSValueConvertible where Element == JSValueConvertible {
    public func jsValue() -> JSValue {
        let array = Array.new(count)
        for (index, element) in self.enumerated() {
            array[index] = element.jsValue()
        }
        return .object(array)
    }
}

extension RawJSValue: JSValueConvertible {
    public func jsValue() -> JSValue {
        switch kind {
        case JavaScriptValueKind_Invalid:
            fatalError()
        case JavaScriptValueKind_Boolean:
            return .boolean(payload1 != 0)
        case JavaScriptValueKind_Number:
            return .number(Double(bitPattern: UInt64(payload1) | (UInt64(payload2) << 32)))
        case JavaScriptValueKind_String:
            // +1 for null terminator
            let buffer = malloc(Int(payload2 + 1))!.assumingMemoryBound(to: UInt8.self)
            defer { free(buffer) }
            _load_string(payload1 as JavaScriptObjectRef, buffer)
            buffer[Int(payload2)] = 0
            let string = String(decodingCString: UnsafePointer(buffer), as: UTF8.self)
            return .string(string)
        case JavaScriptValueKind_Object:
            return .object(JSObjectRef(id: payload1))
        case JavaScriptValueKind_Null:
            return .null
        case JavaScriptValueKind_Undefined:
            return .undefined
        case JavaScriptValueKind_Function:
            return .function(JSFunctionRef(id: payload1))
        default:
            fatalError("unreachable")
        }
    }
}

extension JSValue {
    func withRawJSValue<T>(_ body: (inout RawJSValue) -> T) -> T {
        let kind: JavaScriptValueKind
        let payload1: JavaScriptPayload
        let payload2: JavaScriptPayload
        switch self {
        case let .boolean(boolValue):
            kind = JavaScriptValueKind_Boolean
            payload1 = boolValue ? 1 : 0
            payload2 = 0
        case let .number(numberValue):
            kind = JavaScriptValueKind_Number
            payload1 = UInt32(numberValue.bitPattern & 0x00000000ffffffff)
            payload2 = UInt32((numberValue.bitPattern & 0xffffffff00000000) >> 32)
        case var .string(stringValue):
            kind = JavaScriptValueKind_String
            return stringValue.withUTF8 { bufferPtr in
                let ptrValue = UInt32(UInt(bitPattern: bufferPtr.baseAddress!))
                var rawValue = RawJSValue(kind: kind, payload1: ptrValue, payload2: JavaScriptPayload(bufferPtr.count))
                return body(&rawValue)
            }
        case let .object(ref):
            kind = JavaScriptValueKind_Object
            payload1 = ref._id
            payload2 = 0
        case .null:
            kind = JavaScriptValueKind_Null
            payload1 = 0
            payload2 = 0
        case .undefined:
            kind = JavaScriptValueKind_Undefined
            payload1 = 0
            payload2 = 0
        case let .function(functionRef):
            kind = JavaScriptValueKind_Function
            payload1 = functionRef._id
            payload2 = 0
        }
        var rawValue = RawJSValue(kind: kind, payload1: payload1, payload2: payload2)
        return body(&rawValue)
    }
}



extension Array where Element == JSValueConvertible {
    func withRawJSValues<T>(_ body: ([RawJSValue]) -> T) -> T {
        func _withRawJSValues<T>(
            _ values: [JSValueConvertible], _ index: Int,
            _ results: inout [RawJSValue], _ body: ([RawJSValue]) -> T) -> T {
            if index == values.count { return body(results) }
            return values[index].jsValue().withRawJSValue { (rawValue) -> T in
                results.append(rawValue)
                return _withRawJSValues(values, index + 1, &results, body)
            }
        }
        var _results = [RawJSValue]()
        return _withRawJSValues(self, 0, &_results, body)
    }
}

extension Array where Element: JSValueConvertible {
    func withRawJSValues<T>(_ body: ([RawJSValue]) -> T) -> T {
        Swift.Array<JSValueConvertible>.withRawJSValues(self)(body)
    }
}
