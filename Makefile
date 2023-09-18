BULMA_CSS_VER := 0.9.1
STATIC_CSS = static/css
SASS = sass

${SASS}/bulma-${BULMA_CSS_VER}:
	mkdir -p ${SASS}
	curl -L -o /tmp/bulma.zip https://github.com/jgthms/bulma/releases/download/${BULMA_CSS_VER}/bulma-${BULMA_CSS_VER}.zip
	unzip -uo /tmp/bulma.zip -d ${SASS}/bulma-${BULMA_CSS_VER}
	rm -r ${SASS}/bulma-${BULMA_CSS_VER}/bulma/css
	bash rename_bulma_sass.sh ${SASS}/bulma-${BULMA_CSS_VER}

.PHONY: build
build: ${SASS}/bulma-${BULMA_CSS_VER}
	zola build

.PHONY: clean
clean:
	rm -r public

.PHONY: serve
serve:
	zola serve --drafts