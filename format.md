### タイトル

先頭のタイトルは

    第 3 回 I/O 仮想化「デバイス I/O 編」

次のように変換します。

    \documentclass[a4j,12pt]{jarticle}
    \usepackage[dvips]{graphicx}
    \title{第 3 回 I/O 仮想化「デバイス I/O 編」}
    \author{Takuya ASADA syuu@dokukino.com}
    \begin{document}
    \maketitle

また文章の終わりに次の文を追加します。

    \end{document}


### 章

章はsectionで囲みます

    ハイパーバイザによるI/O デバイスエミュレーション方法

次のようになります。

    \section{ハイパーバイザによるI/O デバイスエミュレーション方法}


### 節

\subsectionで囲みます。

    シリアルポートの受信処理

次のようになります。

    \subsection{シリアルポートの受信処理}


### ソースコード

* \begin{figure}で囲みます。
* \begin{verbatim}の中にソースコードを記述します。
* \caption{}にリストXXと記載します。

例

    \begin{figure}
    \begin{verbatim}
    
    unsigned char read_com1(void) {
      while ((read_reg_byte(COM1_LSR) & 1) == 0);
      return read_reg_byte(COM1_RBR);
    }
    
    \end{verbatim}
    \caption{▼リスト 1  シリアルポートの受信処理}
    \end{figure}

### 図

* \begin{figure}で囲みます。
* works/figuresディレクトリにあるepsファイルをfiguresにコピーします。
* \includegraphics{}で図を取り込みします。
* \caption{}に図XXと記載します。

このようになります。

    \begin{figure}
    \includegraphics{figures/part3_fig1_IO_bitmaps.eps}
    \caption{I/O-bitmap と I/O アドレス空間}
    \label{fig1}
    \end{figure}


### 脚注

脚注直後に、\footnoteで囲って脚注を記述します。



    EPTでもシャドーペー
    ジングの場合と同様にオーバーヘッドが発生しま
    す。\footnote[3]{
    EPT が一般的にシャドーページングより高い性能が出せない
    という意味ではなく、メモリーマップド I/O に限っては性能が
    変わらないという意味です。
    }
    
### 箇条書き

浅田さんは、\subsection*をご利用なさっていたので、確認をした方がよいでしょう。


    \begin{enumerate}
    
    \item{ページフォルト例外発生時のRIP
      \footnote[2]{
      RIP は実行中の命令のアドレスを持つレジスタ。 32bit モードでは EIP と呼ばれます。
      }
    をVMCSのGuest-State AreaのRIPフィールドから取得}
    \item{ゲストマシンのメモリ空間へアクセスして命令のバイト列を読み込み}
    \item{命令をデコードしてアクセスサイズ、アクセス方向、データの書き込み先・読み込み元を取得}
    \item{3の情報を元にしてデバイスアクセスのエミュレーションを実行}
    \end{enumerate}


### 表

works/tablesに.xlsx形式で置いてあります（但し、まだ欠品があります）。


    \begin{table}
    \begin{tabular}{|l|l|} \hline
    \end{tabular}
    \caption{▼表 1   Exit Reason 30 のときの Exit qualification}
    \end{table}
    
### ライセンス

    \section{ライセンス}
    Copyright (c) 2014 Takuya ASADA.
    全ての原稿データ は クリエイティブ・コモンズ 表示 - 継承 4.0 国際 ライセンスの下に提供されています。
    
### その他

* アンダースコアとシャープは先頭に\\をつけます。

