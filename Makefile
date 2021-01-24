PAPER_CSS_VER := v1.8.2
STATIC_CSS = static/css

${STATIC_CSS}/paper.css:
	mkdir -p ${STATIC_CSS}
	curl -L -o ${STATIC_CSS}/paper.css https://github.com/rhyneav/papercss/releases/download/${PAPER_CSS_VER}/paper.css 
	curl -L -o ${STATIC_CSS}/paper.min.css https://github.com/rhyneav/papercss/releases/download/${PAPER_CSS_VER}/paper.min.css

.PHONY: build
build: ${STATIC_CSS}/paper.css