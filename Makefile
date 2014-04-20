all:
	platex part1.tex
	platex part1.tex
	dvipdfmx part1.dvi
	latex2html part1.tex

clean:
	rm -rf *.aux *.dvi *.log *.pdf part1/
