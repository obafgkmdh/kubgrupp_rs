rchit := $(patsubst resources/shaders/%,resources/shaders/spv/%.spv,$(wildcard resources/shaders/*.rchit))
rmiss := $(patsubst resources/shaders/%,resources/shaders/spv/%.spv,$(wildcard resources/shaders/*.rmiss))
rgen := $(patsubst resources/shaders/%,resources/shaders/spv/%.spv,$(wildcard resources/shaders/*.rgen))
rint := $(patsubst resources/shaders/%,resources/shaders/spv/%.spv,$(wildcard resources/shaders/*.rint))
glsl := $(wildcard resources/shaders/*.glsl)

shaders := $(rchit) $(rmiss) $(rgen) $(rint)

all: $(shaders)

clean:
	rm resources/shaders/spv/*.spv

$(shaders): resources/shaders/spv/%.spv: resources/shaders/% $(glsl)
	glslc $< --target-spv=spv1.6 -o $@

