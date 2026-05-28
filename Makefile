config ?= debug

GET_DEPENDENCIES_WITH := corral fetch
CLEAN_DEPENDENCIES_WITH := corral clean
COMPILE_WITH := corral run -- ponyc

BUILD_DIR ?= build/$(config)

ifdef config
	ifeq (,$(filter $(config),debug release))
		$(error Unknown configuration "$(config)")
	endif
endif

ifeq ($(config),release)
	PONYC_FLAGS =
else
	PONYC_FLAGS = --debug
endif

PONYC = $(COMPILE_WITH) $(PONYC_FLAGS)

COMPILER_BIN := $(BUILD_DIR)/gir-compiler
DOCS_BIN := $(BUILD_DIR)/gir-docs

SHARED_SOURCES := $(shell find gir scanner planner emitter doc_translate \
                     -name '*.pony' 2>/dev/null)
COMPILER_SOURCES := $(shell find bin -name '*.pony' 2>/dev/null)
DOCS_SOURCES := $(shell find gir-docs -name '*.pony' 2>/dev/null)
EMBEDDED_SOURCES := $(shell find embedded -name '*.pony' 2>/dev/null)
BAKED := emitter/embedded_resources.pony

all: build

build: $(COMPILER_BIN) $(DOCS_BIN)

compiler: $(COMPILER_BIN)
docs: $(DOCS_BIN)

$(COMPILER_BIN): $(SHARED_SOURCES) $(COMPILER_SOURCES) $(BAKED) | $(BUILD_DIR)
	$(GET_DEPENDENCIES_WITH)
	$(PONYC) --bin-name gir-compiler -o $(BUILD_DIR) bin

$(DOCS_BIN): $(SHARED_SOURCES) $(DOCS_SOURCES) $(BAKED) | $(BUILD_DIR)
	$(GET_DEPENDENCIES_WITH)
	$(PONYC) --bin-name gir-docs -o $(BUILD_DIR) gir-docs

$(BAKED): $(EMBEDDED_SOURCES) tools/bake_embedded.sh
	tools/bake_embedded.sh > $(BAKED)

test: build
	@echo "(no automated tests yet — run smoke checks manually)"
	$(COMPILER_BIN) --version
	$(DOCS_BIN) --version

clean:
	$(CLEAN_DEPENDENCIES_WITH)
	rm -rf $(BUILD_DIR)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

.PHONY: all build compiler docs test clean
