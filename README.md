Software Design誌の連載「ハイパーバイザの作り方」の原稿公開用リポジトリ
==========================
こちらは記事のPDF・HTML作成用元データです。
公開中の記事を読みたい方は[こちら](http://syuu1228.github.io/howto_implement_hypervisor/)。

# ファイルの配置
- 各回の原稿データ(Plain text, utf8) : work/partX.txt
- 各回の図データ : work/figures/partX_figX.*
- 各回の表データ : work/tables/partX.*
- 公開用Markdownデータ(pandoc, utf8) : partX.md
- 公開用TeXデータに貼る図データ(eps,png) : figures/partX_figX.*

# ビルド方法
- texliveベースのplatex環境とpandoc環境をセットアップしてmakeコマンドを実行（※新しいファイルを追加した場合はMakefileにも追加して下さい）。
- Markdownのフォーマットに関しては[こちら](format.md)を参考

# コントリビューション方法
- このgitリポジトリをforkしてファイルを変更、commit & pushしてpull requestを送って下さい。
- 現在、テキストの原稿データを起こしているところでTeX化が進んでいません。 テキスト原稿データをMarkdown化してpull req頂けると助かります。
- 原稿に誤りを見つけた場合もissuesやpull reqでご指摘ください。
