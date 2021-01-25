PAPER_CSS_VER := v1.8.2
BULMA_CSS_VER := 0.9.1
STATIC_CSS = static/css
SASS = sass

${STATIC_CSS}/paper.css:
	mkdir -p ${STATIC_CSS}
	curl -L -o ${STATIC_CSS}/paper.css https://github.com/rhyneav/papercss/releases/download/${PAPER_CSS_VER}/paper.css 
	curl -L -o ${STATIC_CSS}/paper.min.css https://github.com/rhyneav/papercss/releases/download/${PAPER_CSS_VER}/paper.min.css

${SASS}/bulma-${BULMA_CSS_VER}:
	mkdir -p ${SASS}
	curl -L -o /tmp/bulma.zip https://github.com/jgthms/bulma/releases/download/${BULMA_CSS_VER}/bulma-${BULMA_CSS_VER}.zip
	unzip -uo /tmp/bulma.zip -d ${SASS}/bulma-${BULMA_CSS_VER}
	rm -r ${SASS}/bulma-${BULMA_CSS_VER}/bulma/css
	bash rename_bulma_sass.sh ${SASS}/bulma-${BULMA_CSS_VER}

.PHONY: build
build: ${STATIC_CSS}/paper.css ${SASS}/bulma-${BULMA_CSS_VER}
	zola build