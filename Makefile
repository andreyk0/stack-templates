build: compile generate

compile:
	cd template-project && stack test

generate: rio-app.hsfiles

%.hsfiles:
	./template-project/make-template.hs template-project/$* $@
