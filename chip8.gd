extends Control
const FONT_DATA: PackedByteArray = [
	0xF0, 0x90, 0x90, 0x90, 0xF0, # 0
	0x20, 0x60, 0x20, 0x20, 0x70, # 1
	0xF0, 0x10, 0xF0, 0x80, 0xF0, # 2
	0xF0, 0x10, 0xF0, 0x10, 0xF0, # 3
	0x90, 0x90, 0xF0, 0x10, 0x10, # 4
	0xF0, 0x80, 0xF0, 0x10, 0xF0, # 5
	0xF0, 0x80, 0xF0, 0x90, 0xF0, # 6
	0xF0, 0x10, 0x20, 0x40, 0x40, # 7
	0xF0, 0x90, 0xF0, 0x90, 0xF0, # 8
	0xF0, 0x90, 0xF0, 0x10, 0xF0, # 9
	0xF0, 0x90, 0xF0, 0x90, 0x90, # A
	0xE0, 0x90, 0xE0, 0x90, 0xE0, # B
	0xF0, 0x80, 0x80, 0x80, 0xF0, # C
	0xE0, 0x90, 0x90, 0x90, 0xE0, # D
	0xF0, 0x80, 0xF0, 0x80, 0xF0, # E
	0xF0, 0x80, 0xF0, 0x80, 0x80  # F
]
const KEY_MAP: Dictionary[Key, int] = {
	KEY_1: 0x1, KEY_2: 0x2, KEY_3: 0x3, KEY_4: 0xC,
	KEY_Q: 0x4, KEY_W: 0x5, KEY_E: 0x6, KEY_R: 0xD,
	KEY_A: 0x7, KEY_S: 0x8, KEY_D: 0x9, KEY_F: 0xE,
	KEY_Z: 0xA, KEY_X: 0x0, KEY_C: 0xB, KEY_V: 0xF
}

@export_file("*.ch8") var file: String:
	set(f):
		file = f
		if ram.size() > 4000:
			load_program()
@export var screen: TileMapLayer
@export var label_registers_location: GridContainer
@export var opcode_label: Label
@export var hz: int = 60
@export var emulate_old_shift: bool = false
@export var emulate_buggy_jump_offset: bool = false
@export var emulate_old_load_store: bool = true

var ram: PackedByteArray # pre 200 is internal stuff
var stack: Array[int]
var stack_pointer: int = 0:
	set(i):
		if i > 16:
			push_error("Stack Overflow!")
			return
var input: Array[bool]
var v_registers: PackedByteArray
var i_register: int = 0
var program_counter: int
var delay_timer: int
var sound_timer: int

func _ready() -> void:
	ram.resize(4096)
	stack.resize(16)
	input.resize(16)
	v_registers.resize(16)
	for i in range(FONT_DATA.size()):
		var ram_idx: int = i + 0x50
		ram[ram_idx] = FONT_DATA[i]
	load_program()
	program_counter = 0x200
	_delay_timer()

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if KEY_MAP.has(event.keycode):
			var key = KEY_MAP[event.keycode]
			if key < input.size():
				input[key] = event.pressed

func load_program() -> void:
	if file:
		var program: PackedByteArray = FileAccess.get_file_as_bytes(file)
		for i in range(program.size()):
			var ram_idx: int = i + 0x200
			ram[ram_idx] = program[i]


func _process(delta: float) -> void:
	for i in range(hz / 60):
		_run()
	for i in v_registers.size():
		var children: Array[Label]
		children.assign(label_registers_location.get_children())
		children[i].text = "%X" % v_registers[i]
	opcode_label.text = "%X" % ((ram[program_counter] << 8) | ram[program_counter + 1])


func _run() -> void:
	if program_counter > ram.size() -2:
		program_counter = 0x160
	var opcode: int = (ram[program_counter] << 8) | ram[program_counter + 1]
	var first_nibble: int = opcode & 0xF000
	var x: int = (opcode & 0x0F00) >> 8
	var y: int = (opcode & 0x00F0) >> 4 # Note to myself: shift to the nibble pos -1 multiplied by 4
	var n: int = opcode & 0x000F		# Example: if 1000: >> 12, if 0100: >> 8, if 0010: >> 4, if 0001: none (?)
	var nn: int = opcode & 0x00FF
	var nnn: int = opcode & 0x0FFF
	program_counter += 2
	match first_nibble:
		0x0000:
			if nn == 0x00E0: # Screen clear
				screen.clear()
			elif nn == 0x00EE: # Return from subroutine
				program_counter = stack[stack.size() - 1]
				stack.pop_back()
		0x1000: # Jump to NNN
			program_counter = nnn
		0x2000: # Subroutine to NNN
			stack.append(program_counter)
			program_counter = nnn
		0x3000: # If value is equal to register X then skip next instruction
			var value = v_registers[x]
			if value == nn:
				program_counter += 2
		0x4000: # If value is not equal to register X then skip next instruction
			var value = v_registers[x]
			if value != nn:
				program_counter += 2
		0x5000: # If register X is equal to register Y then skip next instruction
			var value_x = v_registers[x]
			var value_y = v_registers[y]
			if value_x == value_y:
				program_counter += 2
		0x6000: # Set register X to nn
			_set_register(x, nn)
		0x7000: # Set register X to Register V plus NN
			_set_register(x, v_registers[x] + nn)
		0x8000: # Maths
			var register_x = v_registers[x]
			var register_y = v_registers[y]
			match n:
				0x0000: # Set register X to Register Y
					_set_register(x, register_y)
				0x0001: # Set register X to binary OR of register X and register Y
					_set_register(x, register_x | register_y)
				0x0002: # Set register X to binary AND of register X and register Y
					_set_register(x, register_x & register_y)
				0x0003: # Set register X to binary XOR of register X and register Y
					_set_register(x, register_x ^ register_y)
				0x0004: # Add register x and register y and save to register x. if sum is above 255 then set the carry flag.
					var sum: int = register_x + register_y
					_set_register(x, sum)
					if sum > 255:
						_set_register(0x0F, 1)
					else:
						_set_register(0x0F, 0)
				0x0005: # Substract register x and register y and save to register x. if sum is above or equal to 255 then set the carry flag.
					_set_register(x, register_x - register_y)
					if register_x >= register_y:
						_set_register(0x0F, 1)
					else:
						_set_register(0x0F, 0)
				0x0006: # Set register x to register x or register y if old_shift, bitshift it to the right by one, set the flag.
					if emulate_old_shift:
						_set_register(x, register_y)
					else:
						_set_register(x, register_x >> 1)
					_set_register(0x0F, register_x & 0x1)
				0x0007: # Substract register x and register y and save to register x. if sum is above 255 then set the carry flag.
					_set_register(x, register_y - register_x)
					if register_x > register_y:
						_set_register(0x0F, 0)
					else:
						_set_register(0x0F, 1)
				0x000E: # Set register x to register x or register y if old_shift, bitshift it to the left by one, set the flag.
					if emulate_old_shift:
						_set_register(x, register_y)
					else:
						_set_register(x, register_x << 0x1)
					_set_register(0x0F, (register_x & 0x80) >> 7)
		0x9000: # If register x is not equal to register y then skip next instruction
			var value_x = v_registers[x]
			var value_y = v_registers[y]
			if value_x != value_y:
				program_counter += 2
		0xA000: # Sets the I register to NNN
			i_register = nnn
		0xB000: # Jumps to NNN plus value from register 0 if emulating the buggy offset, to register X if not.
			var address: int
			if emulate_buggy_jump_offset:
				address = nnn + v_registers[x]
			else:
				address = nnn + v_registers[0]
			program_counter = address
		0xC000: # Sets register X to a random value from 0 to 255, and bit AND it by NN.
			_set_register(x, randi_range(0, 255) & nn)
		0xD000: # Draws on screen, register X is the X coordinate, register Y is Y, N is the height.
			_draw_instruction(v_registers[x], v_registers[y], n)
		0xE000:
			match nn:
				0x009E: # If input key on the index of register X is pressed skip one instruction.
					if input[v_registers[x]] == true:
						program_counter += 2
				0x00A1: # If input key on the index of register X is not pressed skip one instruction.
					if input[v_registers[x]] == false:
						program_counter += 2
		0xF000:
			match nn:
				0x000A: # Stops execution until any key is pressed, and writed the idx of the key to the register X.
					program_counter -= 2 
					for i in input.size():
						if input[i] == true:
							_set_register(x, i)
							program_counter += 2
							break
				0x0007: # Sets the register X to the delay timer.
					_set_register(x, delay_timer)
				0x0015: # Sets the delay_timer to the register X.
					delay_timer = v_registers[x]
				0x0018: # Sets the sound_timer to the register X.
					sound_timer = v_registers[x]
				0x001E: # Sets the I Register to the register X.
					i_register += v_registers[x]
				0x0029: # Sets the I Register to the location of the specified letter in the font block.
					i_register = 0x50 + (5 * v_registers[x])
				0x0033: # Separates the hex value to each digit in binary, stores them sequentially.
					var value: int = v_registers[x]
					ram[i_register] = value / 100
					ram[i_register + 1] = (value / 10) % 10
					ram[i_register + 2] = value % 10
				0x0055: # Saves the contents of registers starting from value X to Ram, if old is then it increments I Register to X + 1
					for i in range(x + 1):
						ram[i_register + i] = v_registers[i]
					if emulate_old_load_store:
						i_register += x + 1
				0x0065: # Loads the contents of Ram starting from value X to Registers, if old is then it increments I Register to X + 1
					for i in range(x + 1):
						v_registers[i] = ram[i_register + i]
					if emulate_old_load_store:
						i_register += x + 1


func _draw_instruction(x: int, y: int, height: int) -> void:
	x = x % 64
	y = y % 32
	v_registers[0xF] = 0 
	for row in height:
		var byte = ram[i_register + row]
		for i in range(0, 8):
			var cords := Vector2i(x + i, y + row)
			if cords.x >= 64 or cords.y >= 32:
				continue
			var sprite_pixel_on: bool = (byte >> (7 - i)) & 1
			var is_pixel_on: bool = screen.get_cell_tile_data(cords) != null
			if not sprite_pixel_on:
				continue
			if is_pixel_on:
				v_registers[0xF] = 1 
				screen.set_cell(cords, -1)
			else:
				screen.set_cell(cords, 0, Vector2i(0, 0))



func _delay_timer() -> void:
	while true:
		if delay_timer != 0:
			delay_timer -= 1
		if sound_timer != 0:
			sound_timer -= 1
			$AudioStreamPlayer.play()
		await get_tree().create_timer(0.016).timeout


func _set_register(idx: int, value: int) -> void:
	v_registers[idx] = value & 0xFF
