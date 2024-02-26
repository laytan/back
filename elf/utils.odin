package elf

import "core:reflect"
import "core:io"

// import "vendor:zlib"

is_enum_known_value :: proc(value: any) -> bool {
	int_value, ok := reflect.as_i64(value)
	assert(ok)

	ti := reflect.type_info_base(type_info_of(value.id)).variant.(reflect.Type_Info_Enum)
	for v in ti.values {
		if int_value == i64(v) {
			return true
		}
	}

	return false
}

// inflate :: proc(dest, src: io.Stream, n: int) -> (err: Error) {
// 	n := n
//
// 	inp: [1024]byte
// 	out: [1024]byte
//
// 	strm: zlib.z_stream
// 	if zlib.inflateInit(&strm, 0) != zlib.OK {
// 		return .Decompress_Failure
// 	}
// 	defer zlib.inflateEnd(&strm)
//
// 	inf_loop: for n > 0 {
// 		strm.avail_in = u32(io.read(src, inp[:min(n, len(inp))]) or_return)
// 		defer n -= int(strm.avail_in)
// 		if strm.avail_in == 0 {
// 			break
// 		}
//
// 		strm.next_in = &inp[0]
//
// 		for {
// 			strm.avail_out = len(out)
// 			strm.next_out  = &out[0]
// 			switch zlib.inflate(&strm, zlib.NO_FLUSH) {
// 			case zlib.OK:
// 			case zlib.STREAM_END: break inf_loop
// 			case:                 return .Decompress_Failure
// 			}
//
// 			have := len(out) - strm.avail_out
// 			write_full(dest, out[:have]) or_return
//
// 			if strm.avail_out != 0 {
// 				break
// 			}
// 		}
// 	}
//
// 	if n != 0 { err = .Decompress_Failure }
//
// 	return
// }

// TODO: needs a place in core honestly.
//
// write_full writes until the entire contents of `buf` has been written or an error occurs.
write_full :: proc(w: io.Writer, buf: []byte) -> (n: int, err: Error) {
	return write_at_least(w, buf, len(buf))
}

// TODO: needs a place in core honestly.
//
// write_at_least writes at least `buf[:min]` to the writer and returns the amount written.
// If an error occurs before writing everything it is returned.
write_at_least :: proc(w: io.Writer, buf: []byte, min: int) -> (n: int, err: Error) {
	if len(buf) < min {
		return 0, .Short_Buffer
	}
	for n < min && err == nil {
		nn: int
		nn, err = io.write(w, buf[n:])
		n += nn
	}

	if err == nil && n < min {
		err = .Short_Write
	}
	return
}
