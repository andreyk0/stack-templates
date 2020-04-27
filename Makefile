.PHONY: build
build: compile generate

.PHONY: compile
compile:
	cd template-project && stack test

.PHONY: generate
generate: \
	clean \
	rio-app.hsfiles

.PHONY: clean
clean:
	-rm -f *.hsfiles

%.hsfiles:
	./template-project/make-template.hs template-project/$* $@
