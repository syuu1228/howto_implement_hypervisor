all:
	platex part1.tex
	platex part1.tex
	dvipdfmx part1.dvi

	platex part3.tex
	platex part3.tex
	dvipdfmx part3.dvi

	latex2html part1.tex
	latex2html part3.tex

clean:
	rm -rf *.aux *.dvi *.log *.pdf part1/
