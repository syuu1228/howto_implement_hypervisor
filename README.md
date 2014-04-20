howto_implement_hypervisor
==========================

Software Design誌の連載「ハイパーバイザの作り方」の原稿公開用リポジトリ

ファイルの配置
- 各回の原稿データ(Plain text, utf8) : work/partX.txt
- 各回の図データ : work/figures/partX_figX.*
- 公開用TeXデータ(platex, utf8) : partX.tex
- 公開用TeXデータに貼る図データ : figures/partX_figX.*

TeXビルド方法
- texliveベースのplatex環境をセットアップしてmakeコマンドを実行。
