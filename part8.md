# 第8回 Intel VT-xを用いたハイパーバイザの実装その3「vmm.koによるVMEntry」


## はじめに

前回は、/usr/sbin/bhyveの初期化とVMインスタンスの実行機能の実装について解説しました。今回はvmm.koがVM_RUN ioctlを受け取ってからVMEntryするまでの処理を解説します。

## 解説対象のソースコードについて

本連載では、FreeBSD-CURRENTに実装されているBHyVeのソースコードを解説しています。
このソースコードは、FreeBSDのSubversionリポジトリから取得できます。
リビジョンはr245673を用いています。

お手持ちのPCにSubversionをインストールし、次のようなコマンドでソースコードを取得してください。

svn co -r245673 svn://svn.freebsd.org/base/head src

## /usr/sbin/bhyveによる仮想CPUの実行処理の復習

/usr/sbin/bhyveは仮想CPUの数だけスレッドを起動し、それぞれのスレッドが/dev/vmm/${name}に対してVM_RUN ioctlを発行します(図[fig1])。
vmm.koはioctlを受けてCPUをVMX non root modeへ切り替えゲストOSを実行します(VMEntry)。


![VM_RUN ioctl による仮想CPUの実行イメージ](figures/part8_fig1 "図1")

VMX non root modeでハイパーバイザの介入が必要な何らかのイベントが発生すると制御がvmm.koへ戻され、イベントがトラップされます(VMExit)。

イベントの種類が/usr/sbin/bhyveでハンドルされる必要のあるものだった場合、ioctlはリターンされ、制御が/usr/sbin/bhyveへ移ります。
イベントの種類が/usr/sbin/bhyveでハンドルされる必要のないものだった場合、ioctlはリターンされないままゲストCPUの実行が再開されます。
今回の記事では、vmm.koにVM_RUN ioctlが届いてからVMX non root modeへVMEntryするまでを見ていきます。


### vmm.koがVM_RUN ioctlを受け取ってからVMEntryするまで

vmm.koがVM_RUN ioctlを受け取ってからVMEntryするまでの処理について、順を追って見ていきます。リスト1、リスト2、リスト3、リスト4にソースコードを示します。白丸の数字と黒丸の数字がありますが、ここでは白丸の数字を追って見ていきます。

### VMExit時の再開アドレス

(19)でCPUはVMX non-root modeへ切り替わりゲストOSが実行されますが、ここからVMExitした時にCPUはどこからホストOSの実行を再開するので しょうか。
直感的にはvmlaunchの次の命令ではないかと思いますが、そうではありません。
VT-xでは、VMEntry時にVMCSのGUEST_RIPからVMX non- root modeの実行を開始し、VMExit時にVMCSのHOST_RIPからVMX root modeの実行を開始することになっています。
GUEST_RIPはVMExit時に保存されますが、HOST_RIPはVMEntry時に保存されません。

このため、VMCSの初期化時に指定されたHOST_RIPが常にVMExit時の再開アドレスとなります。
では、VMCSのHOST_RIPがどのように初期化されているか、順を追って見ていきます。
リスト1、リスト2、リスト3、リスト4にソースコードを示します。
今度は黒丸の数字を追って見ていきます。


#### リスト1の解説

vmm_dev.cは、sysctlによる/dev/vmm/${name}の作成・削除と/dev/vmm/${name}に対するopen(), close(), read(), write(), mmap(), ioctl()のハンドラを定義しています。
ここでは/dev/vmm/${name}の作成とVM_RUN ioctlについてのみ見ていきます。

#### リスト2の解説

vmm.cは、IntelVT-xとAMD-Vの2つの異なるハードウェア仮想化支援機能のラッパー関数を提供しています(このリビジョンではラッパーのみが実装されており、AMD-Vの実装は行われていません)。
Intel/AMD両アーキテクチャ向けの各関数はvmm_ops構造体で抽象化され、207〜210行目のコードCPUを判定してどちらのアーキテクチャの関数群を使用するかを決定しています。

#### リスト3の解説

intel/ディレクトリにはIntel VT-xに依存したコード群が置かれています。
vmx.cはその中心的なコードで、vmm.cで登場したvmm_ops_intelもここで定義されています。

#### リスト4の解説

vmcs.cはVMCSの設定に関するコードを提供しています。
ここではHOST_RIPの書き込みに注目しています。
なお、vmwriteを行う前にvmptrld命令を発行していますが、これはCPUへVMCSポインタをセットしてVMCSへアクセス可能にするためです。
同様に、vmwriteを行った後にvmclear命令を発行していますが、これは変更されたVMCSをメモリへライトバックさせるためです。

#### リスト5の解説

vmx_support.SはC言語で記述できない、コンテキストの退避/復帰やVT-x拡張命令の発行などのコードを提供しています。
ここでは、ホストレジスタの退避(vmx_setjmp)とVMEntry(vmx_launch)の処理について見ています。

## まとめ

vmm.koがVM_RUN ioctlを受け取ってからVMEntryするまでにどのような処理が行われているかについて、ソースコードを解説しました。
次回はこれに対応するVMExitの処理について見ていきます。

ライセンス
==========

Copyright (c) 2014 Takuya ASADA. 全ての原稿データ は
クリエイティブ・コモンズ 表示 - 継承 4.0 国際
ライセンスの下に提供されています。
