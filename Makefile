.PHONY: local lint build

local: build
	luarocks make --lua-version=5.1 --local lapis-stats-dev-1.rockspec

build: 
	moonc lapis
 
lint:
	moonc -l lapis

