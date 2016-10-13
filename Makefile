.PHONY: local lint build

local: build
	luarocks make --local lapis-stats-dev-1.rockspec

build: 
	moonc lapis
 
lint:
	moonc -l lapis

