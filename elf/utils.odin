package elf

import "core:reflect"

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
