---
authors:
- 'Takuya ASADA syuu@dokukino.com'
title: |
    ハイパーバイザの作り方～ちゃんと理解する仮想化技術～ 
    第１８回　FreeBSD 10.0-RELEASE公開記念 10.0-RELEASEで学ぶbhyveの使い方
...

はじめに
========
2014年1月20日にbhyveがマージされたFreeBSD10.0がついにリリースされました。今回はこれを記念し、仮想マシンのネットワークデバイスについて解説する予定を変更し、bhyveの使い方をおさらいします。

bhyveとは
==========
bhyveはNetAppにより開発され2011年に発表された、新しいハイパーバイザです。設計はLinux KVMに似ており、大雑把に説明すればKVMのFreeBSD版と言えます。但し、KVMではユーザランドプログラムに既存のエミュレータであるQEMUを流用しているため既存OSとの高い互換性が得られています。しかし、コードの見通しが悪くなってしまっているのが難点として挙げられます。一方、bhyveでは独自に一から実装したユーザランドにより、シンプルで見通しのよいコードを保っています。

bhyveの動作環境
===============
bhyveを試すには、Intel VT-xとEPT（Extended Page Tables）をサポートしたCPUが必要です。
今のところAMDのCPUには対応していません[^1]。

どのモデルのCPUがEPTをサポートしているかはark.intel.comで調べられます。
簡単な目安としては、Core i3, i5, i7ならばほぼ全てのCPUが対応しています。CeleronやPentiumなどの廉価版CPUでもEPT対応モデルが一部存在しています。実機にインストールするのが最も確実ですが、最近のVMware（VMware Player・VMware Workstation・VMware Fusion）ならばNested VMに対応しているため仮想マシン上で試すことも出来ます。

ただし、FreeBSD以外のゲストOSを動作させるためには、上述の条件を満たす環境でも以下のような問題が確認されています。

* VMwareによるNested VM環境へLinuxをゲストOSとして起動しようとすると、タイマ周りの問題でLinuxカーネルがフリーズする
* 古いCore iシリーズ（Nehalem）はunrestricted guest（注：VMでリアルモードをサポートする機能）をサポートしないため、grub2-bhyve（後述）でLinuxやOpenBSDカーネルを起動出来ない
* 一部のバージョンのLinuxカーネルと一部のIntel CPUの組み合わせで非サポートMSRのアクセスによるエラーを起こしてbhyveが異常終了する（後述）

また、bhyveを実行するにはamd64版のFreeBSDを使用する必要があります。32bit版ではサポートされていません。

[^1]: svmブランチで開発が進められています：<http://svnweb.freebsd.org/base/projects/bhyve_svm/sys/?sortby=date&view=log>

bhyveが提供する機能
===================

現状のbhyveでは幾つかのゲストOSをロードし実行するのに最低限の機能のみが実装されています。

ハードディスクコントローラとしてはAHCIコントローラのエミュレーションと、準仮想化ドライバであるvirtio-blkをサポートしています。
NICコントローラは、準仮想化ドライバであるvirtio-netをサポートしており、Intel e1000のような標準的なデバイスエミュレーションはサポートしていません。
virtioは多くの場合、標準的なデバイスのエミュレーションと比較して高い性能が得られますが、ゲストOSにvirtioドライバをインストールされており起動時に使えるように設定する必要があります。

システムコンソールとしてはPCI接続の16550互換シリアルポートをサポートしており、標準的なビデオデバイスはサポートしていません。
また、X11を起動してGUI環境を表示する事はできません。

bhyveがエミュレート可能なデバイスは上述のものだけですが、Intel VT-dを用いて実機上のPCI・PCI Expressデバイスをゲストマシンへパススルー接続できます。

このほか割り込みコントローラのエミュレーション（Local APIC、IO-APIC）や、タイマデバイスのエミュレーション、ハードウェア構成をゲストOSへ伝えるのに必要なAPICなどをサポートしています。

また、BIOSやUEFIなどのファームウェアをサポートしていないため、ディスクイメージからブートローダをロードしてゲストOSを起動する事ができません。このためにハイパーバイザの機能としてゲストOSをロードしゲストマシンを初期化するOSローダが実装されています。

bhyveの構成
============
bhyveはCPUに対してVT-x命令を発行するなどハードウェアに近い処理を行うカーネルモジュール（vmm.ko）と、ユーザランドにおいてユーザインタフェースを提供しハードウェアエミュレーションを行うVM実行プログラム（/usr/sbin/bhyve）の二つからなります。

前述のとおり、bhyveはBIOSやUEFIなどのファームウェアをサポートしておらず、ディスクイメージ上のブートローダーを実行できません。このため、ゲストカーネルをロードして起動可能な状態に初期化するゲストOSローダ(/usr/sbin/bhyveload)が付属します。bhyveではディスクイメージ上のブートローダを実行できないため、ゲストカーネルをロードして起動可能な状態に初期化するゲストOSローダ(/usr/sbin/bhyveload)が付属します。

/usr/sbin/bhyveloadはFreeBSDブートローダをFreeBSD上で実行可能なプログラムに改変し、ゲストマシンのディスクイメージからカーネルを読み込んでゲストメモリ空間へ展開するようにしたものです。

/usr/sbin/bhyveloadを実行すると、FreeBSDのブート時に表示されるのと同じメニューが表示されます。

このため、一見するとゲストマシンの実行が開始されたように見えます。しかし、これはホストOSで/usr/sbin/bhyveloadが出力している画面で、ゲストマシンは起動していません。また、VMインスタンスの削除などを行うためのVMインスタンス管理ツールとして/usr/sbin/bhyvectlが提供されています。

これらのユーザランドのプログラム群は、VM管理用のライブラリ（libvmmapi）を通してvmm.koが提供するデバイスに対してmmapやioctlを発行してゲストマシンの初期化や実行を行います。全体図を図１に示します。

![bhyveの構成](figures/part18_fig1)

grub2-bhyve
===========
前述の/usr/sbin/bhyveloadでは、FreeBSD以外のゲストOSを起動させられません。これを解決するために、GRUB2をFreeBSD上で実行可能なプログラムに改変したgrub2-bhyveが提供されています。grub2-bhyveは/usr/sbin/bhyveloadと異なり汎用OSローダであるため、GRUB2がサポートする各種OSを起動させる事ができます。

これまでに動作が確認されているOSは以下の３つです。
* Linux
* OpenBSD
* FreeBSD（grub2-bhyve経由）

/usr/sbin/bhyveや/usr/sbin/bhyveloadはFreeBSD baseに付属するプログラムであるのに対し、grub2-bhyveはPorts・pkgng経由で提供されるパッケージとなっています。

vmrc
====
vmrcはbhyve-scriptを更に拡張したもので、bhyveの他にjailやQEMUもサポートします。
今回はbhyve-scriptを用いたVMの構築方法について紹介しますが、今後はこちらが主流のツールになる可能性がありそうです。

bhyve-script
============
QEMU/KVMのコマンド引数はユーザにとって分かりづらく、KVMベースの仮想マシンの構築にはlibvirt + virshなどのフロントエンドが多く用いられています。

libvirtは今のところbhyveをサポートしていませんが、その代わりになるような簡易的なシェルスクリプトがbhyve.orgから提供されています。
ダウンロードページへのURLはこちらです：<http://bhyve.org/tools/>

各種ゲストOSのインストール方法
==============================
以下に、FreeBSD 10.0-RELEASEにおける各種ゲストOSのインストール方法を示します。
なお、全てのゲストOSはamd64（x86_64）版であり、32bit版はサポートされていません。

事前に必要な作業
----------------
grub2-bhyveとbhyve-scriptをインストールします。

```
# pkg install grub2-bhyve tmux
# fetch http://bhyve.org/bhyve-script.tar
# tar -xvf bhyve-script.tar
```

Ubuntu 13.10の場合
------------------
```
# cd bhyve-script
# cp vm0 ubuntu0
これから作るVMの名前にvm0をコピー（末尾は数値で、他のVMと重複しない値でなければならない）
# vi ubuntu0
NIC=“em0” をお使いのNIC名に
VCPUS=“1”を任意のvCPU数に
VMRAM=1024”を任意のメモリサイズに
VMOS=“freebsd”を”linuxに
VMOSVER=“9.2-RELEASE”を”ubuntu13.10”に
DEVSIZE=“2G”を任意のディスクサイズに
それぞれ変更。
# sh ubuntu0 iso
ISOファイルがダウンロードされ、ブートローダが起動する。
ネットワークの設定画面でDHCPが失敗するため、「Do not configure the network at this time（ネットワークの設定をしない）」を選択。
パーティーション作成画面では「 Guided - use entire disk （LVMを使わない）」を選択。
# sh ubuntu0 start
HDイメージからUbuntuが起動する。
但し、このままでは端末を閉じるとVMが強制終了してしまう。
これを避けるにはtmuxを使ってバックグラウンドで走らせる必要がある。
tmuxを使うには、以下のようにスクリプトを編集すればよい。
# vi ubuntu0
CONSOLE=“default”を”tmux”または”tmux-detached”に
（tmux-detachedは実行時にtmuxをdetachする設定）
```

Debian 7.3の場合
----------------
VMOSVERを”debian7.3.0”にすれば、Ubuntu 13.10とほぼ同様の手順でインストール可能です。

CentOS 6.5の場合
---------------
```
# cd bhyve-script
# cp vm0 centos1
これから作るVMの名前にvm0をコピー（末尾は数値で、他のVMと重複しない値でなければならない）
# vi centos1
NIC=“em0” をお使いのNIC名に
VCPUS=“1”を任意のvCPU数に
VMRAM=1024”を任意のメモリサイズに
VMOS=“freebsd”を”linuxに
VMOSVER=“9.2-RELEASE”を”centos6.5”に
DEVSIZE=“2G”を任意のディスクサイズに
それぞれ変更。
# sh centos1 iso
ISOファイルがダウンロードされ、ブートローダが起動する。
“Error processing drive: pci-0000:00:02.0-virtio-pci-virtio0”というようなエラーが表示されたら「Re-initialize all」を選択する。
パーティーション設定の画面では「Use entire disk」を選択する。
# sh centos1 start
HDイメージからCentOSが起動する。
```

FreeBSD 9.2-RELEASEの場合
------------------------
```
# cd bhyve-script
# cp vm0 freebsd2
これから作るVMの名前にvm0をコピー（末尾は数値で、他のVMと重複しない値でなければならない）
# vi freebsd2
NIC=“em0” をお使いのNIC名に
VCPUS=“1”を任意のvCPU数に
VMRAM=1024”を任意のメモリサイズに
DEVSIZE=“2G”を任意のディスクサイズに
それぞれ変更。
# sh freebsd2 iso
ISOファイルがダウンロードされ、ブートローダが起動する。
# sh freebsd2 start
HDイメージからFreeBSDが起動する。
```

OpenBSD 5.4の場合
-----------------
OpenBSDサポートはまだ実験段階で、カーネルを改変したバージョンの5.4しか動きません。
そのため、以下のような手順で改変済みディスクイメージを取得・インストールする必要があります。

```
# cd bhyve-script
# cp vm0 openbsd3
これから作るVMの名前にvm0をコピー（末尾は数値で、他のVMと重複しない値でなければならない）
# vi openbsd3
NIC=“em0” をお使いのNIC名に
VCPUS=“1”を任意のvCPU数に
VMOS=“freebsd”を”openbsd”に
VMRAM=1024”を任意のメモリサイズに
それぞれ変更。
# mkdir -p ./vm/openbsd3
# fetch http://people.freebsd.org/~grehan/flashimg.amd64-20131014.bz2
# bunzip2 flashimg.amd64-20131014.bz2
# cp flashimg.amd64-20131014 ./vm/openbsd3/openbsd3.img
# sh openbsd3 start
rootのパスワードは'test123'でログイン可能。
```
インストールのエラー回避方法
----------------------------
一部のLinuxカーネルと一部のIntel CPUの組み合わせでは「Unknown WRMSR code 391, val 2000000f, cpu 0」「vm exit rdmsr 0xe8, cpu 0」などのエラーが出力される場合があります。
これはbhyveの実装上の問題で10.0-RELEASEでは修正されていません、以下の手順でCURRENT上のパッチを取得・適用することで回避できます。

```
# svn co svn://svn.freebsd.org/base/head
# cd head
# svn diff -r259634:r259635 > ~/msr.diff
# cd /usr/src
# patch -p0 < ~/msr.diff
# cd usr.sbin/bhyve
# make
# make install
# cd ~/bhyve-script
# vi centos1
    BHYVECMD="/usr/sbin/bhyve \
        -c "$VCPUS" \
のところを以下のように書き換える：
    BHYVECMD="/usr/sbin/bhyve \
        -w \
        -c "$VCPUS" \
```


まとめ
======
今回はFreeBSD 10.0-RELEASEで実際にいくつものゲストOSを実行する方法を解説しました。
いよいよbhyveが実用的に使えるようになってきたのを実感して頂けたことと思います。
次回は、今号で紹介する予定でした仮想マシンのネットワークデバイスについて解説します。

ライセンス
==========

Copyright (c) 2014 Takuya ASADA. 全ての原稿データ は
クリエイティブ・コモンズ 表示 - 継承 4.0 国際
ライセンスの下に提供されています。
