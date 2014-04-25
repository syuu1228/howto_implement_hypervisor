---
authors:
- 'Takuya ASADA syuu@dokukino.com'
title: |
    ハイパーバイザの作り方～ちゃんと理解する仮想化技術～ 
    第１６回 PCIパススルーその２「VT-dの詳細」
...

## はじめに

前回は、PCIパススルーとIOMMUの概要について解説しました。
今回は、VT-dの詳細について解説していきます。

## 前回のおさらい

PCIデバイスが持つメモリ空間をゲストマシンのメモリ空間にマップすることによりPCIデバイスをパススルー接続できますが、DMAを使用するときに1つ困った問題が生じます。

PCIデバイスはDMA時のアドレス指定にホスト物理アドレスを使用します。ゲストOSは、ゲストOSは自分が持つゲスト物理ページとホスト物理ページの対応情報を持っていないので正しいページ番号をドライバに与えることができません。

そこで、*物理メモリとPCIデバイスの間にMMUのような装置を置きアドレス変換を行う*方法が考え出されました。
このような装置を*IOMMU*と呼びます。
DMA転送時にアドレス変換を行うことで、パススルーデバイスが正しいページへデータを書き込めるようになります（図[fig1]）。
Intel VT-dは、このような機能を実現するためにチップセットへ搭載されたIOMMUです。

![図1, IOMMUを用いたDMA時のアドレス変換](figures/part16_fig1 "図1, IOMMUを用いたDMA時のアドレス変換")

## VT-dの提供する機能

VT-dが提供する機能には、次のようなものが挙げられます。

- IO device assignment：特定のデバイスを特定のVMに割り当てるための機能
- DMA remapping：仮想マシン上へDMAするためにアドレス変換を行う機能
- Interrupt remapping：特定のデバイスから特定のVMへ届くように割り込みをルーティングする機能
- Reliability: DMA・割り込みエラーをシステムソフトウェアに記録・レポートできる

今回はVT-dによるアドレス変換の話を解説することを目的としているため、このうち"DMA remapping"機能に絞って解説を進めていきます[^1]。

なお、VT-dに関するより詳しい内容は"Intel Virtualization Technology for Directed I/O Architecture Specification"という資料にて解説されているので、こちらをご覧下さい[^2]。

[^1]) より正確には、DMA remapping機能のうち"Requests-without-PASID"であるものについてのみ解説しています。
[^2]) <http://www.intel.co.jp/content/www/jp/ja/intelligent-systems/intel-technology/vt-directed-io-spec.html>

### アドレス変換テーブル

VT-dでは、アドレスリマップ対象のデバイスごとにCPUのMMUと同様の多段ページテーブルを持ちます。
デバイスごとのページテーブルを管理するため、PCIデバイスを一意に識別するBus Number・Device Number・Functionの識別子から対応するページテーブルを探すための2段のテーブルを用います。

1段目はRoot Tableと呼ばれ、0から255までのBusナンバーに対応するエントリからなるテーブルです。
このテーブルはアドレス変換時にVT-dから参照するため、Root Table Address Registerへセットされます。
Root Tableエントリのフォーマットを表[tab1]に示します。

Table: 表1, Root table entry format

Root tableエントリはcontext-table pointerフィールドで2段目のテーブルであるContext-tableのアドレスを指します。
Context-tableはRoot tableエントリで示されるBus上に存在するDevice 0-31・Function 0-7の各デバイスに対応するページテーブルを管理しています。
Context-tableエントリのフォーマットを表[tab2]に示します。

----------------------------------------------------------------------------------------------------------------
bits    field                                   description
------- --------------------------------------- ----------------------------------------------------------------
127:88  reserved                                予約フィールド

87:72   domain identifier                       ドメインID このエントリがどのVMに属するかを示す

71      reserved                                予約フィールド

70:67   ignored                                 無視されるフィールド

66:64   address width                           ページテーブルの段数を示す
                                                (0x0:2段、0x1:3段、0x2:4段、0x3:5段、0x4:6段)

63:12   second level page translation pointer   アドレス変換に使用するページテーブルエントリのアドレスを指定する

11:4    reserved                                予約フィールド

3:2     translation type                        アドレス変換時の挙動を設定

1       fault processing disable                0x0 :フォールトレコード・レポートを有効化
                                                0x1 :フォールトレコード・レポートを無効化

0       present                                 このエントリが有効化どうか
----------------------------------------------------------------------------------------------------------------

Table: 表2, Context-table entry format

Context-tableエントリはsecond level page translation pointerでページテーブルのアドレスを指します。
ページテーブルの段数はaddress widthフィールドで指定されます。
図[fig2]に4段ページテーブル・4KBページを使用する場合のアドレス変換テーブルの全体図を示します。
ここで使用されるページテーブルエントリのフォーマットは通常のページテーブルエントリと若干異なるのですが、ここでは解説は割愛します。

![図2, VT-dのアドレス変換テーブル全体図(例)](figures/part16_fig2 "図2, VT-dのアドレス変換テーブル全体図(例)")

### フォールト

変換対象になるアドレスに対する有効なページ割り当てが存在しない場合、または対象ページへのアクセス権がない場合、VT-dはフォールトを起こします。
フォールトが発生した場合、メモリアクセスを行おうとしたPCIデバイスはアクセスエラーを受け取ります。
OSへは、MSI割り込みを使用して通知されます。

### IOTLB

IOMMUのアドレス変換を高速に行うには、通常のMMUと同じようにアドレス変換結果のキャッシュが必要です。
通常のMMUではこのような機構のことをTLBを呼びますが、IOMMUではIOTLBと呼びます。
通常のMMUのTLBでは、TLBエントリが古くなったときにinvalidateと呼ばれる操作によりエントリを削除します。
このときのinvalidateの粒度は、グローバルなinvalidate・プロセス単位のinvalidate([^3])・ページ単位のinvalidateなどが選べます。
VT-dのIOTLBでは、グローバルなinvalidate・デバイス単位のinvalidate・VM単位（ドメインと呼ばれる）のinvalidate・ページ単位のinvalidateが行えるようになっています。

[^3]) Tagged TLBの場合。

### Context-cache

IOTLBに類似していますが、VT-dではContext-table entryもキャッシュされています。これについても場合によってinvalidate操作が必要になります。

## DMARによるIOMMUの通知

DMAリマッピング機能がハードウェア上に存在することをOSに伝えるため、ACPIはDMARと呼ばれるテーブルを用意しています。
DMARでは、いくつかの異なる種類の情報が列挙されています。

IOMMUはDMA Remapping Hardware Unit Definition(DRHD)という名前の構造体で記述されており、他にDMAに用いることのできない予約済みメモリ領域を示すReserved Memory Region Reporting(RMRR)などが存在します。
DRHDはIOMMUのレジスタベースアドレスと、IOMMUがDMAリマッピング対象にしているPCIデバイスのリストを持ちます。

VT-dの設定をOS上から簡単に確認することは難しいですが、ACPIテーブルは簡単に見ることができるので、ここでその方法を説明します。
例としてUbuntu LinuxでDMARを表示するコマンドを画面1に示します。

```
画面1 DMAR表示コマンド(Ubuntu Linux)
$ sudo apt-get install iasl
$ sudo cp /sys/firmware/acpi/tables/DMAR .
$ sudo iasl -d DMAR
Intel ACPI Component Architecture
AML Disassembler version 20100528 [Dec 19 2012]
Copyright (c) 2000 - 2010 Intel Corporation
Supports ACPI Specification Revision 4.0a
Loading Acpi table from file DMAR
Acpi Data Table [DMAR] decoded, written to "DMAR.dsl"
syuu@hiratake:~$ cat DMAR.dsl
/*
* Intel ACPI Component Architecture
* AML Disassembler version 20100528
*
* Disassembly of DMAR, Mon Nov 25 09:11:42 2013
*
* ACPI Data Table [DMAR]
*
* Format: [HexOffset DecimalOffset ByteLength]  FieldName : FieldValue
*/
[000h 0000  4]                    Signature : "DMAR"    /* DMA Remapping table */
[004h 0004  4]                 Table Length : 00000130
[008h 0008  1]                     Revision : 01
[009h 0009  1]                     Checksum : 22
[00Ah 0010  6]                       Oem ID : "AMI"
[010h 0016  8]                 Oem Table ID : "OEMDMAR"
[018h 0024  4]                 Oem Revision : 00000001
[01Ch 0028  4]              Asl Compiler ID : "MSFT"
[020h 0032  4]        Asl Compiler Revision : 00000097
[024h 0036  1]           Host Address Width : 26
[025h 0037  1]                        Flags : 01
[030h 0048  2]                Subtable Type : 0000 <Hardware Unit Definition>
[032h 0050  2]                       Length : 0020
[034h 0052  1]                        Flags : 01
[035h 0053  1]                     Reserved : 00
[036h 0054  2]           PCI Segment Number : 0000
[038h 0056  8]        Register Base Address : 00000000FBFFE000
[040h 0064  1]      Device Scope Entry Type : 03
[041h 0065  1]                 Entry Length : 08
[042h 0066  2]                     Reserved : 0000
[044h 0068  1]               Enumeration ID : 06
[045h 0069  1]               PCI Bus Number : F0
[046h 0070  2]                     PCI Path : [1F, 07]
[048h 0072  1]      Device Scope Entry Type : 03
[049h 0073  1]                 Entry Length : 08
[04Ah 0074  2]                     Reserved : 0000
[04Ch 0076  1]               Enumeration ID : 07
[04Dh 0077  1]               PCI Bus Number : 00
[04Eh 0078  2]                     PCI Path : [13, 00]
[050h 0080  2]                Subtable Type : 0001 <Reserved Memory Region>
[052h 0082  2]                       Length : 0058
[054h 0084  2]                     Reserved : 0000
[056h 0086  2]           PCI Segment Number : 0000
[058h 0088  8]                 Base Address : 00000000000EC000
[060h 0096  8]          End Address (limit) : 00000000000EFFFF
〜　略　〜
```

Hardware Unit Definitionと表示されているのがDRHDで、Reserved Memory Regionと表示されているのがRMRRです。

このテーブルの情報が誤っていると、BIOSとカーネルでVT-dを有効にしてもLinuxカーネルがエラーを起こしてPCIパススルーが正常に動作しない場合があります[^4]。

[^4]) この場合、ユーザの設定ミスではなくBIOSのバグなので、対策としてはサーバベンダからBIOSアップデートを受け取るか、カーネル側でDMARを無視して強引に初期化するような方法しかありません。

### VT-dのレジスタ

VT-dで使用される主なレジスタを表3に示します。
VT-dのレジスタはメモリマップドでアクセスでき、ベースアドレスは前述のDMAR上のDRHDで通知されます。

表3, VT-dの主なレジスタ

### VT-dの有効化

VT-dを有効化し、DMAリマップを行うには以下のような手順で設定を行います。

xxxxx設定完了までウエイトするために、global status registerのtranslation enable statusにビットが立つまでループします。

1. メモリ上にルートテーブル、コンテキストテーブルを作成
2. root table address registerにroot tableのアドレスを設定し、global command registerにset root table pointerをセット（表４）してroot tableのアドレスを設定します。
設定完了までウエイトするために、global status registerのroot table pointer statusにビットが立つまで（表５）ループします
3. IOTLB、Context-cacheをinvalidateします（細かい手順は省略します）
4. global command registerにtranslation enableをセットしてDMAリマッピングを有効化します xxxxx

bits|field|description
-|-|-
31|translation enable|DMA remapping 有効・無効化
30|set root table pointer|root table pointer のセット・アップデート
29|set fault log|fault log pointer のセット・アップデート
28|enable advanced fault logging|advanced fault logging 有効・無効化
27|write buffer flush|write buffer を flush
26|queued invalidation enable|queue invalidation 有効・無効化
25|interrupt remapping enable|interrupt remaping 有効・無効化
24|set interrupt remap table pointer|interrupt remap table pointer のセット・アップデート
23|compatibility format interrupt|compatibility format interrupt 有効・無効化
22:00|reserved|予約フィールド

Table: 表4, global command register

|bits|field|description|
|-|-|-|
|31|translation enable status|DMA remappingの状態|
|30|root table pointer status|root table pointerの状態|
|29|fault log status|fault log pointerの状態|
|28|advanced fault logging status|advanced fault loggingの状態|
|27|write buffer flush status|write buffer flushの状態|
|26|queued invalidation enable status|queue invalidation enableの状態|
|25|interrupt remapping enable status|interrupt remapingの状態|
|24|interrupt remap table pointer status|interrupt remap table pointerの状態|
|23|compatibility format interrupt status|compatibility format interruptの状態|
|22:00|reserved|予約フィールド|

Table: 表5, global status register

## まとめ

今回は、VT-dの詳細について解説しました。
次回からは、よりソフトウェア寄りの視点から仮想化を解説していきたいと思います。

ライセンス
==========

Copyright (c) 2014 Takuya ASADA. 全ての原稿データ は
クリエイティブ・コモンズ 表示 - 継承 4.0 国際
ライセンスの下に提供されています。
