# ハイパーバイザの作り方
第１６回 PCIパススルー その2「VT-dの詳細」
はじめに
前回は、PCIパススルーとIOMMUの概要について解説しました。
今回は、VT-dの詳細について解説していきます。
前回のおさらい
　PCIデバイスが持つメモリ空間をゲストマシンの
メモリ空間にマップすることによりPCIデバイスを
パススルー接続できますが、DMAを使用するときに 
1つ困った問題が生じます。
　PCIデバイスはDMA時のアドレス指定にホスト
物理アドレスを使用します。ゲストOSは、ゲスト 
OSは自分が持つゲスト物理ページとホスト物理
ページの対応情報を持っていないので正しいページ
番号をドライバに与えることができません。
　そこで、物理メモリとPCIデバイスの間にMMU
のような装置を置きアドレス変換を行う方法が考え
出されました。このような装置をIOMMUと呼びま
す。DMA転送時にアドレス変換を行うことで、パス
スルーデバイスが正しいページへデータを書き込め
るようになります（図[fig1]）。Intel VT-dは、このような
機能を実現するためにチップセットへ搭載された 
IOMMUです。
図１，IOMMUを用いたDMA時のアドレス変換
VT-dの提供する機能
VT-dが提供する機能には、次のようなものが挙げられます。
・IO device assignment：特定のデバイスを特定のVMに割り当てるための機能
・DMA remapping：仮想マシン上へDMAするためにアドレス変換を行う機能
・Interrupt remapping：特定のデバイスから特定のVMへ届くように割り込みをルーティングする機能
・Reliability: DMA・割り込みエラーをシステムソフトウェアに記録・レポートできる
今回はVT-dによるアドレス変換の話を解説することを目的としているため、このうち”DMA remapping”機能に絞って解説を進めていきます(1)。
なお、VT-dに関するより詳しい内容は”Intel Virtualization Technology for Directed I/O Architecture Specification”という資料にて解説されているので、こちらをご覧下さい(2)。
より正確には、DMA remapping機能のうち”Requests-without-PASID”であるものについてのみ解説しています。
http://www.intel.co.jp/content/www/jp/ja/intelligent-systems/intel-technology/vt-directed-io-spec.html
アドレス変換テーブル
　VT-dでは、アドレスリマップ対象のデバイスご
とにCPUのMMUと同様の多段ページテーブルを持
ちます。デバイスごとのページテーブルを管理する
ため、PCIデバイスを一意に識別するBus Number・
Device Number・Functionの識別子から対応するペー
ジテーブルを探すための2段のテーブルを用います。
　1段目はRoot Tableと呼ばれ、0から255までの
Busナンバーに対応するエントリからなるテーブル
です。このテーブルはアドレス変換時にVT-dから
参照するため、Root Table Address Registerへセッ
トされます。Root Tableエントリのフォーマットを
表[tab1]に示します。
表１，Root table entry format
　Root tableエントリはcontext-table pointerフィー
ルドで2段目のテーブルであるContext-tableのアド
レスを指します。Context-tableはRoot tableエントリ
で示されるBus上に存在するDevice 0-31・Function 
0-7の各デバイスに対応するページテーブルを管理
しています。Context-tableエントリのフォーマット
を表[tab2]に示します。
表２，Context-table entry format
　Context-tableエントリはsecond level page translation 
pointerでページテーブルのアドレスを指します。
ページテーブルの段数はaddress widthフィールドで
指定されます。図[fig2]に4段ページテーブル・4KBページ
を使用する場合のアドレス変換テーブルの全体図を示
します。ここで使用されるページテーブルエントリ
のフォーマットは通常のページテーブルエントリと
若干異なるのですが、ここでは解説は割愛します。
図２，VT-dのアドレス変換テーブル全体図（例）
フォールト
　変換対象になるアドレスに対する有効なページ割り
当てが存在しない場合、または対象ページへのアクセ
ス権がない場合、 
VT-dはフォールトを起こします。
フォールトが発生した場合、メモリアクセスを行おう
とした 
PCIデバイスはアクセスエラーを受け取りま
す。 
OSへは、 
MSI割り込みを使用して通知されます。 
IOTLB
　IOMMUのアドレス変換を高速に行うには、通常
のMMUと同じようにアドレス変換結果のキャッ
シュが必要です。通常の 
MMUではこのような機構
のことを 
TLBを呼びますが、 
IOMMUでは 
IOTLBと
呼びます。通常の 
MMUのTLBでは、 
TLBエントリ
が古くなったときに 
invalidateと呼ばれる操作によ
りエントリを削除します。このときの 
invalidateの
粒度は、グローバルな 
invalidate・プロセス単位の 
invalidate([^3])・ページ単位の 
invalidateなどが選べま
す。 
VT-dのIOTLBでは、グローバルな 
invalidate・
デバイス単位の 
invalidate・VM単位（ドメインと呼ば
れる）の 
invalidate・ページ単位の 
invalidateが行える
ようになっています。 
[^3]） Tagged TLBの場合。
Context-cache
　IOTLBに類似していますが、 
VT-dでは 
Context-
table entryもキャッシュされています。これについ
ても場合によって 
invalidate操作が必要になります。
DMARによるIOMMUの通知
　DMAリマッピング機能がハードウェア上に存在
することを 
OSに伝えるため、 
ACPIはDMARと呼ば
れるテーブルを用意しています。 
DMARでは、いく
つかの異なる種類の情報が列挙されています。 
IOMMUは 
DMA Remapping Hardware Unit 
Definition（DRHD）という名前の構造体で記述されて
おり、他に 
DMAに用いることのできない予約済み
メモリ領域を示す 
Reserved Memory Region Reporting（RMRR）などが存在します。 
DRHDは 
IOMMUのレジスタベースアドレスと、 
IOMMUが 
DMAリマッピング対象にしている 
PCIデバイスの
リストを持ちます。
　VT-dの設定を 
OS上から簡単に確認することは難
しいですが、 
ACPIテーブルは簡単に見ることができ
るので、ここでその方法を説明します。例として 
Ubuntu LinuxでDMARを表示するコマンドを画面1
に示します。
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
　Hardware Unit Definitionと表示されているのが 
DRHDで、 
Reserved Memory Regionと表示されてい
るのが 
RMRRです。
　このテーブルの情報が誤っていると、 
BIOSとカー
ネルで 
VT-dを有効にしても 
Linuxカーネルがエ
ラーを起こして 
PCIパススルーが正常に動作しない
場合があります[^4]。 
[^4]） この場合、ユーザの設定ミスではなくBIOSのバグなので、対
策としてはサーバベンダからBIOSアップデートを受け取る
か、カーネル側でDMARを無視して強引に初期化するような
方法しかありません。
VT-dのレジスタ
VT-dで使用される主なレジスタを表３に示します。
VT-dのレジスタはメモリマップドでアクセスでき、ベースアドレスは前述のDMAR上のDRHDで通知されます。
表３，VT-dの主なレジスタ
VT-dの有効化
VT-dを有効化し、DMAリマップを行うには以下のような手順で設定を行います。
１，メモリ上にルートテーブル、コンテキストテーブルを作成
２，root table address registerにroot tableのアドレスを設定し、global command registerにset root table pointerをセット（表４）してroot tableのアドレスを設定します 設定完了までウエイトするために、global status registerのroot table pointer statusにビットが立つまで（表５）ループします
３，IOTLB、Context-cacheをinvalidateします（細かい手順は省略します）
４，global command registerにtranslation enableをセットしてDMAリマッピングを有効化します 設定完了までウエイトするために、global status registerのtranslation enable statusにビットが立つまでループします
表４，global command register
表５，global status register
まとめ
今回は、VT-dの詳細について解説しました。
次回からは、よりソフトウェア寄りの視点から仮想化を解説していきたいと思います。ライセンス
==========

Copyright (c) 2014 Takuya ASADA. 全ての原稿データ は
クリエイティブ・コモンズ 表示 - 継承 4.0 国際
ライセンスの下に提供されています。
