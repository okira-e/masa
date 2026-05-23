APP := masa

build:
	mkdir -p bin/debug
	odin build . -out:bin/debug/$(APP)

test:
	odin test lexer
	odin test ast
	odin test parser
	odin test interpreter
	
release: # Usage: make release TARGET=linux_amd64, windows_amd64, darwin_arm64
	mkdir -p bin/release
	odin build . \
		-out:bin/release/$(APP) \
		-target:$(TARGET) \
		-o:speed \
		-no-bounds-check \
		-disable-assert