package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"
	"unicode/utf8"
)

// A Value is a JSON value as jq holds it: nil for null, a bool, a Number, a
// string, a []Value or an *Object. The store keeps every row as one, so a row's
// fields keep the order and the spelling jq gives them, whatever fields a
// fixture writes.
type Value = any

// A Number is a JSON number by its literal text. jq 1.8 keeps a number's
// decimal digits and prints the literal in its canonical form, which Compact
// writes.
type Number string

// An Object is a JSON object whose keys keep the order jq keeps: the order they
// were first written in. Setting a key it holds keeps the key's place, and a
// new key goes last.
type Object struct {
	keys []string
	vals map[string]Value
}

// NewObject returns an empty object.
func NewObject() *Object { return &Object{vals: map[string]Value{}} }

// Get returns the value under k, and whether the object holds k.
func (o *Object) Get(k string) (Value, bool) {
	v, ok := o.vals[k]
	return v, ok
}

// Set writes v under k.
func (o *Object) Set(k string, v Value) {
	if _, ok := o.vals[k]; !ok {
		o.keys = append(o.keys, k)
	}
	o.vals[k] = v
}

// Del removes k, and is a no-op when the object does not hold it.
func (o *Object) Del(k string) {
	if _, ok := o.vals[k]; !ok {
		return
	}
	delete(o.vals, k)
	for i, x := range o.keys {
		if x == k {
			o.keys = append(o.keys[:i:i], o.keys[i+1:]...)
			break
		}
	}
}

// Keys returns the object's keys in order.
func (o *Object) Keys() []string { return o.keys }

// Clone returns a copy of o whose own keys can change without changing o. The
// values are shared.
func (o *Object) Clone() *Object {
	c := &Object{keys: append([]string(nil), o.keys...), vals: make(map[string]Value, len(o.vals))}
	for k, v := range o.vals {
		c.vals[k] = v
	}
	return c
}

// Decode reads exactly one JSON value from data.
func Decode(data []byte) (Value, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	v, err := decodeValue(dec)
	if err != nil {
		return nil, err
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return nil, errors.New("more than one JSON value")
	}
	return v, nil
}

// DecodeStream reads every JSON value in data, in order.
func DecodeStream(data []byte) ([]Value, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	var out []Value
	for {
		v, err := decodeValue(dec)
		if errors.Is(err, io.EOF) {
			return out, nil
		}
		if err != nil {
			return out, err
		}
		out = append(out, v)
	}
}

func decodeValue(dec *json.Decoder) (Value, error) {
	tok, err := dec.Token()
	if err != nil {
		return nil, err
	}
	switch t := tok.(type) {
	case json.Delim:
		switch t {
		case '[':
			arr := []Value{}
			for dec.More() {
				v, err := decodeValue(dec)
				if err != nil {
					return nil, err
				}
				arr = append(arr, v)
			}
			if _, err := dec.Token(); err != nil {
				return nil, err
			}
			return arr, nil
		case '{':
			obj := NewObject()
			for dec.More() {
				kt, err := dec.Token()
				if err != nil {
					return nil, err
				}
				k, ok := kt.(string)
				if !ok {
					return nil, fmt.Errorf("an object key that is not a string: %v", kt)
				}
				v, err := decodeValue(dec)
				if err != nil {
					return nil, err
				}
				obj.Set(k, v)
			}
			if _, err := dec.Token(); err != nil {
				return nil, err
			}
			return obj, nil
		}
		return nil, fmt.Errorf("an unexpected %v", t)
	case json.Number:
		return Number(t), nil
	default:
		return t, nil
	}
}

// Truthy is jq's truth: every value but null and false.
func Truthy(v Value) bool {
	switch t := v.(type) {
	case nil:
		return false
	case bool:
		return t
	}
	return true
}

// Compact is v as `jq -c` prints it.
func Compact(v Value) string {
	var b strings.Builder
	writeCompact(&b, v)
	return b.String()
}

// compactRawControl is v as Compact prints it, but with each C0 control
// character in a string written as its raw byte where Compact escapes it, as
// an answer that carries one arrives.
func compactRawControl(v Value) string {
	var b strings.Builder
	writeValue(&b, v, true)
	return b.String()
}

func writeCompact(b *strings.Builder, v Value) { writeValue(b, v, false) }

func writeValue(b *strings.Builder, v Value, rawControl bool) {
	switch t := v.(type) {
	case nil:
		b.WriteString("null")
	case bool:
		b.WriteString(strconv.FormatBool(t))
	case Number:
		b.WriteString(canonicalNumber(string(t)))
	case string:
		writeStringAs(b, t, rawControl)
	case []Value:
		b.WriteByte('[')
		for i, x := range t {
			if i > 0 {
				b.WriteByte(',')
			}
			writeValue(b, x, rawControl)
		}
		b.WriteByte(']')
	case *Object:
		b.WriteByte('{')
		for i, k := range t.keys {
			if i > 0 {
				b.WriteByte(',')
			}
			writeStringAs(b, k, rawControl)
			b.WriteByte(':')
			writeValue(b, t.vals[k], rawControl)
		}
		b.WriteByte('}')
	default:
		panic(fmt.Sprintf("fakegc: a value of type %T", v))
	}
}

// Raw is v as `jq -r` prints it: a string as its text, and any other value
// indented by two spaces.
func Raw(v Value) string {
	if s, ok := v.(string); ok {
		return s
	}
	var b strings.Builder
	writePretty(&b, v, 0)
	return b.String()
}

func writePretty(b *strings.Builder, v Value, depth int) {
	indent := func(d int) {
		b.WriteByte('\n')
		for range d {
			b.WriteString("  ")
		}
	}
	switch t := v.(type) {
	case []Value:
		if len(t) == 0 {
			b.WriteString("[]")
			return
		}
		b.WriteByte('[')
		for i, x := range t {
			if i > 0 {
				b.WriteByte(',')
			}
			indent(depth + 1)
			writePretty(b, x, depth+1)
		}
		indent(depth)
		b.WriteByte(']')
	case *Object:
		if len(t.keys) == 0 {
			b.WriteString("{}")
			return
		}
		b.WriteByte('{')
		for i, k := range t.keys {
			if i > 0 {
				b.WriteByte(',')
			}
			indent(depth + 1)
			writeString(b, k)
			b.WriteString(": ")
			writePretty(b, t.vals[k], depth+1)
		}
		indent(depth)
		b.WriteByte('}')
	default:
		writeCompact(b, v)
	}
}

// ToString is jq's tostring: a string as itself, and any other value as its
// compact JSON.
func ToString(v Value) string {
	if s, ok := v.(string); ok {
		return s
	}
	return Compact(v)
}

// writeString writes s as jq writes a string: a quote and a backslash escaped,
// a control character or DEL as \b, \t, \n, \f, \r or a \u escape, and every
// other character as itself.
func writeString(b *strings.Builder, s string) { writeStringAs(b, s, false) }

// writeStringAs writes s as writeString does, or with rawControl each C0
// control character as its raw byte.
func writeStringAs(b *strings.Builder, s string, rawControl bool) {
	b.WriteByte('"')
	for i := 0; i < len(s); {
		r, size := utf8.DecodeRuneInString(s[i:])
		i += size
		switch {
		case rawControl && r < 0x20:
			b.WriteRune(r)
		case r == '"':
			b.WriteString(`\"`)
		case r == '\\':
			b.WriteString(`\\`)
		case r == '\b':
			b.WriteString(`\b`)
		case r == '\t':
			b.WriteString(`\t`)
		case r == '\n':
			b.WriteString(`\n`)
		case r == '\f':
			b.WriteString(`\f`)
		case r == '\r':
			b.WriteString(`\r`)
		case r < 0x20 || r == 0x7f:
			fmt.Fprintf(b, `\u%04x`, r)
		default:
			b.WriteRune(r)
		}
	}
	b.WriteByte('"')
}

// canonicalNumber is a JSON number literal as jq 1.8 prints it: the decimal
// number's scientific string, which keeps the literal's digits, writes an
// exponent as E+n or E-n, and writes a positive exponent, or a small enough
// negative one, in that form rather than as plain digits.
func canonicalNumber(lit string) string {
	sign := ""
	s := lit
	if strings.HasPrefix(s, "-") {
		sign, s = "-", s[1:]
	}
	exp := 0
	if i := strings.IndexAny(s, "eE"); i >= 0 {
		e, err := strconv.Atoi(strings.TrimPrefix(s[i+1:], "+"))
		if err != nil {
			return lit
		}
		exp, s = e, s[:i]
	}
	intPart, frac, _ := strings.Cut(s, ".")
	digits := strings.TrimLeft(intPart+frac, "0")
	if digits == "" {
		digits = "0"
	}
	exp -= len(frac)
	adjusted := exp + len(digits) - 1
	if exp <= 0 && adjusted >= -6 {
		if exp == 0 {
			return sign + digits
		}
		point := len(digits) + exp
		if point > 0 {
			return sign + digits[:point] + "." + digits[point:]
		}
		return sign + "0." + strings.Repeat("0", -point) + digits
	}
	out := digits[:1]
	if len(digits) > 1 {
		out += "." + digits[1:]
	}
	if adjusted >= 0 {
		return sign + out + "E+" + strconv.Itoa(adjusted)
	}
	return sign + out + "E" + strconv.Itoa(adjusted)
}
