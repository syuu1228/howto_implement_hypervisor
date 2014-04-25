.PHONY: all clean part1 part2 part3 part4 part4_5 part5 part6 part7 part8 part9 part10 part11 part12 part15 part16 part17 part18 part19 part20

all: part1 part2 part3 part4 part4_5 part5 part6 part7 part8 part9 part10 part11 part12 part15 part16 part17 part18 part19 part20

part1: part1.pdf part1.html part1.epub part1.mobi
part1.tex: figures/part1_fig1.eps figures/part1_fig2.eps figures/part1_fig3.eps figures/part1_fig4.eps 
part1.html: figures/part1_fig1.png figures/part1_fig2.png figures/part1_fig3.png figures/part1_fig4.png

part2: part2.pdf part2.html part2.epub part2.mobi
part2.tex: figures/part2_fig1.eps figures/part2_fig2.eps figures/part2_fig3.eps figures/part2_fig4.eps figures/part2_fig5.eps figures/part2_fig6.eps figures/part2_fig7.eps
part2.html: figures/part2_fig1.png figures/part2_fig2.png figures/part2_fig3.png figures/part2_fig4.png figures/part2_fig5.png figures/part2_fig6.png figures/part2_fig7.png

part3: part3.pdf part3.html part3.epub part3.mobi
part3.tex: figures/part3_fig1.eps
part3.html: figures/part3_fig1.png

part4: part4.pdf part4.html part4.epub part4.mobi
part4.tex: figures/part4_fig1.eps figures/part4_fig2.eps
part4.html: figures/part4_fig1.png figures/part4_fig2.png

part4_5: part4_5.pdf part4_5.html part4_5.epub part4_5.mobi

part5: part5.pdf part5.html part5.epub part5.mobi
part5.tex: figures/part5_fig1.eps
part5.html: figures/part5_fig1.png

part6: part6.pdf part6.html part6.epub part6.mobi
part6.tex: figures/part6_fig1.eps
part6.html: figures/part6_fig1.png

part7: part7.pdf part7.html part7.epub part7.mobi
part7.tex: figures/part7_fig1.eps
part7.html: figures/part7_fig1.png

part8: part8.pdf part8.html part8.epub part8.mobi
part8.tex: figures/part8_fig1.eps
part8.html: figures/part8_fig1.png

part9: part9.pdf part9.html part9.epub part9.mobi
part9.tex: figures/part9_fig1.eps
part9.html: figures/part9_fig1.png

part10: part10.pdf part10.html part10.epub part10.mobi
part10.tex: figures/part10_fig1.eps
part10.html: figures/part10_fig1.png

part11: part11.pdf part11.html part11.epub part11.mobi
part11.tex: figures/part11_fig1.eps
part11.html: figures/part11_fig1.png

part12: part12.pdf part12.html part12.epub part12.mobi
part12.tex: figures/part12_fig1.eps figures/part12_fig2.eps figures/part12_fig3.eps figures/part12_fig4.eps figures/part12_fig5.eps
part12.html: figures/part12_fig1.png figures/part12_fig2.png figures/part12_fig3.png figures/part12_fig4.png figures/part12_fig5.png

part13: part13.pdf part13.html part13.epub part13.mobi

part14: part14.pdf part14.html part14.epub part14.mobi

part15: part15.pdf part15.html part15.epub part15.mobi
part15.tex: figures/part15_fig1.eps figures/part15_fig2.eps figures/part15_fig3.eps figures/part15_fig4.eps
part15.html: figures/part15_fig1.png figures/part15_fig2.png figures/part15_fig3.png figures/part15_fig4.png

part16: part16.pdf part16.html part16.epub part16.mobi
part16.tex: figures/part16_fig1.eps figures/part16_fig2.eps
part16.html: figures/part16_fig1.png figures/part16_fig2.png

part17: part17.pdf part17.html part17.epub part17.mobi

part18: part18.pdf part18.html part18.epub part18.mobi
part18.tex: figures/part18_fig1.eps
part18.html: figures/part18_fig1.png

part19: part19.pdf part19.html part19.epub part19.mobi
part19.tex: figures/part19_fig1.eps figures/part19_fig2.eps
part19.html: figures/part19_fig1.png figures/part19_fig2.png

part20: part20.pdf part20.html part20.epub part20.mobi

clean:
	rm -fv *.tex *.aux *.dvi *.log *.pdf *.html *.epub *.mobi *.out figures/*.png

%.png: %.eps
	convert $< $@

%.pdf: %.dvi
	dvipdfmx $<

%.dvi: %.tex
	platex $<
	platex $<

%.tex: %.md
	pandoc $< -s -o $@ -V documentclass=jsarticle -V classoption=a4j --default-image-extension=.eps --filter pandoc-citeproc

%.html: %.md
	pandoc $< -s -o $@ --default-image-extension=.png --filter pandoc-citeproc

%.epub: %.md %.html
	pandoc $< -s -o $@ --default-image-extension=.png --filter pandoc-citeproc

%.mobi: %.epub
	-~/kindlegen/kindlegen $<
