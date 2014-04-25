---
authors:
- 'Takuya ASADA syuu@dokukino.com'
title: |
    ハイパーバイザの作り方～ちゃんと理解する仮想化技術～ 
    第１１回 virtioによる準仮想化デバイス その１「virtioの概要とVirtio PCI」
references:
- id: part1
  title: 第１回 x86アーキテクチャにおける仮想化の歴史とIntel VT-x
  URL: 'http://syuu1228.github.io/howto_implement_hypervisor/part1.pdf'
...

# はじめに

前回までに、ハイパーバイザでのI/O仮想化の実装を、BHyVeのソースコードを例に挙げ解説してきました。今回は、ゲストOSのI/Oパフォーマンスを大きく改善する「virtio」準仮想化ドライバの概要と、virtioのコンポーネントの1つである「Virtio PCI」について解説します。

#  完全仮想化デバイスと準仮想化デバイス

x86アーキテクチャを仮想化する手法として、「準仮想化」と呼ばれる方式があります。これは、Xenによって実装された方式です @part1。

準仮想化では、仮想化に適した改変をゲストOSに加えます。これにより、改変を加えずゲストOSを仮想化する完全仮想化と比較し、高いパフォーマンスが得られるようになります。この準仮想化では、ハードウェア仮想化支援も必要としていませんでした。

現在では、先に説明した準仮想化よりも完全仮想化が広く使われるようになっています。これは、ハードウェア仮想化支援機能を持つ CPUが普及し、多くの環境で高速なハードウェア支援機能が利用できるようになったためです。

しかし、完全仮想化を採用したハイパーバイザにおいても、部分的に準仮想化の概念を取り入れています。その部分としては、システム全体のパフォーマンスに大きく影響を及ぼす仮想デバイスが挙げられます。

このような仮想デバイスのことを「準仮想化デバイス」と呼びます。これに対して、実ハードウェアと同じデバイスをエミュレーションしている仮想デバイスのことを「完全仮想化デバイス」と呼びます。

完全仮想化デバイスでは、実ハードウェア向けのOSに付属しているデバイスドライバをそのまま使用できま。しかし、準仮想化デバイスではゲスト環境向けに、準仮想化デバイス用のデバイスドライバをインストールする必要があります。

準仮想化デバイスのフレームワークとして「virtio」があります。これは、特定のハイパーバイザやゲストOSに依存しないフレームワークです。その仕様やソースコードは公開されているため、ハイパーバイザ側ではKVM・VirtualBox・lguest・BHyVeなど、ゲストOS側で はLinux・FreeBSD・NetBSD・OpenBSD・Windows・MonaOSなど多くの実装が存在しています。

また、XenやVMware、Hyper-Vなどのハイパーバイザでも、同様の考え方を採用した準仮想化ドライバが採用されています[^1]。

[^1]: virtioとは異なる独自方式のドライバが用いられています。

# 完全仮想化デバイスが遅い理由

実機上でネットワークインターフェースやブロックデバイスなどに対してI/Oを行う場合、OSはデバイスドライバを介して各デバイスのハードウェアレジスタに対して読み書きを行います。

前回までの記事で解説したとおり、Intel VT-xではこのハードウェアレジスタに対するアクセスを検知するたびにVMExitを行います。ハイパーバイザはVMExitを受けてデバイスエミュレーション処理を行います。

この一連の処理は仮想化を行うときだけに発生するオーバーヘッドであり、この部分の処理の重さが実機と比較した時のI/O性能の差に現れてきます。

より詳細には次のようなコストが発生し、実機上のI/Oと比較してレイテンシが大きくなる可能性があります。

## VMX non-root mode・VMX root mode間のモード遷移にかかるコスト

ハードウェアレジスタアクセス時のVMExitとゲスト再開時のVMEntryでは、それぞれVMX non-root modeとVMX root modeの間でモード遷移が発生します。この遷移のコストはCPUの進化に伴い小さくなってきているものの、VMExit・VMEntryにそれぞれ1000サイクルほど消費します。

## デバイスエミュレータの呼び出しにかかるコスト

多くの場合、ハイパーバイザのデバイスエミュレータはユーザプロセス上で動作しています。このため、ハードウェアレジスタアクセスをエミュレートするにはカーネルモードからユーザモードへ遷移し、エミュレーションを行ってからカーネルモード
へ戻ってくる必要があります。

また、ユーザプロセスはプロセススケジューラが適切と判断したタイミングで実行されるため、VMExit直後にデバイスエミュレータのプロセスが実行される保証はありません。

同様に、ゲスト再開のVMEntryについてもデバイスエミュレーション終了直後に行われる保証はなく、スケジューリング待ちになる可能性もあります。

また、たいていの完全仮想化デバイスでは一度のI/Oに複数回レジスタアクセスを行う必要があります(たとえば、あるNICの受信処理では5〜6回のレジスタアクセスが必要になります)。レジスタアクセスを行うたびに、上述の処理が発生し、大きなコストがかかります。高速なI/Oが求められるデバイスの場合には、ここが性能上のボトルネックになります。

# virtioの概要

virtioは前述のようなデバイスの完全仮想化にかかるコストを減らすため、ホスト・ゲスト間で共有されたメモリ領域上に置いたキューを通じてデータの入出力を行います。

VMExitはキューへデータを送り出したときに、ハイパーバイザへ通知を行う目的でのみ行われ、なおかつハイパーバイザ側がキュー上のデータを処理中であれば通知を抑制することも可能す。このため、完全仮想化デバイスと比較して大幅にモード遷移回数が削減されています。

virtioは、大きく分けてVirtio PCIとVirtqueueの2つのコンポーネントからなります。

Virtio PCIはゲストマシンに対してPCIデバイスとして振る舞い、以下のような機能を提供します。

 - デバイス初期化時のホスト<->ゲスト間ネゴシエーションや設定情報通知に使うコンフィギュレーションレジスタ
 - 割り込み(ホスト->ゲスト)、I/Oポートアクセス(ゲスト->ホスト)によるホスト<->ゲスト間イベント通知機構
 - 標準的なPCIデバイスのDMA機構を用いたデータ転送機能

Virtqueueはデータ転送に使われるゲストメモリ空間上のキュー構造です。デバイスごとに1つまたは複数のキューを持つことができます。たとえば、virtio-netは送信用キュー・受信用キュー・コントロール用キューの3つを必要とします。

ゲストOSは、PCIデバイスとしてvirtioデバイスを検出して初期化し、Virtqueueをデータの入出力に、割り込みとI/Oポートアクセスをイベント通知に用いてホストに対してI/Oを依頼します。

今回の記事では、このうちVirtio PCIについてより詳しく見ていきましょう。

# PCIのおさらい

Virtio PCIの解説を行う前に、まずは簡単にPCIについておさらいしましょう。

PCIデバイスはBus Number・Device Numberで一意に識別され、1つのデバイスが複数の機能を有する場合はFunction Numberで個々の機能が一意に識別されます。

これらのデバイスはPCI Configuration Space、PCI I/O Space、PCI Memory Spaceの3つのメモリ空間を持ちます。

PCI Configuration Spaceはデバイスがどこのメーカーのどの機種であるかを示すVendor ID・Device IDや、PCI I/O Space・PCI Memory Spaceのマップ先アドレスを示すBase Address Register、MSI割り込みの設定情報など、デバイスの初期化とドライバのロードに必要な情報を多数含んでいます。

PCI Configuration Spaceにアクセスするには、次のような手順を実施する必要があります。
1. デバイスのBus Number・Device Number・Function Numberとアクセスしたい領域のオフセット値をEnable BitとともにCONFIG_ADDRESSレジスタ[^2]にセットする。CONFIG_ADDRESSレジスタのビット配置は表1のとおり
2. CONFIG_DATAレジスタ[^3]に対して読み込みまたは書き込みを行う

OSはPCIデバイス初期化時に、Bus Number・Device Numberをイテレートして順にPCI Configuration Spaceを参照することで、コンピュータに接続されているPCIデバイスを検出できます。

 PCI I/O SpaceはI/O空間にマップされており、おもにデバイスのハードウェアレジスタをマップするなどの用途に使われているようです[^4]。

 図1のようにPCI Memory Spaceは物理アドレス空間にマップされており、ビデオメモリなど大きなメモリ領域を必要とする用途に使われているようです。どちらの領域もマップ先はPCI Configuration SpaceのBase Address Registerを参照して取得する必要があります。

  ビットポジション   内容
  ------------------------ --------------------------------------------------------
  31                       Enable Bit
  30-24                    Reserved
  23-18                    Bus Number
  15-11                    Device Number
  10-8                     Function Number
  7-2                      Register offset
  1-0                      0

 Table: CONFIG_ADDRESS register

![PCI Configuration Space](figures/part11_fig1)

[^2]: PCではCONFIG_ADDRESSレジスタはI/O空間の0xCF8にマップされています。
[^3]: PCではCONFIG_DATAレジスタはI/O空間の0xCFCにマップされています。
[^4]: PCではI/O空間にマップされますが、他のアーキテクチャではメモリマップされる場合もあります。

# Virtio PCI デバイスの検出方法

virtioデバイスはゲストマシンに接続されているPCIデバイスとしてゲストOSから認識されます。

 この際、PCI Configuration SpaceのVendor IDは0x1AF4、Device IDは0x1000 - 0x1040の値が渡されます。さらに、virtioデバイスの種類を判別するための追加情報として、表2のようなSubsystem Device IDが渡されます。

ゲストOSはこれらのIDを見て適切なvirtio用ドライバをロードします。

  Subsystem Device ID      device type
  ------------------------ --------------------------------------------------------
  1                        network card
  2                        block device
  3                        console
  4                        entropy source
  5                        memory balooning
  8                        SCSI host
  9                        9P transport

 Table: Subsystem Device ID

# Virtio Header

 Virtio HeaderはPCI I/O Spaceの先頭に置かれたvirtioデバイスの設定用のフィールドで、ゲストOSがvirtioデバイスドライバを初期化するときに利用されます(表3)。
Virtio Headerの終端部分(MSIが無効の場合は20byte、有効の場合は24byte)からはdevice specific headerが続きます。

 表4にvirtio-netのdevice specific headerを示します。

  offset  field name        bytes direction  description
  ------- ----------------- ----- ---------- -----------------------------------------
  0       HOST_FEATURES     4     RO         ホストが対応する機能のビットフィールド
  4       GUEST_FEATURES    4     RW         ゲストが有効にしたい機能のビットフィールド
  8       QUEUE_PFN         4     RW         QUEUE_SELで指定されたキューに割り当てる
                                             メモリ領域の物理ページ番号（PFN）
  12      QUEUE_NUM         2     RO         QUEUE_SELで指定されたキューのサイズ
  14      QUEUE_SEL         2     RW         キュー番号
  16      QUEUE_NOTIFY      2     RW         QUEUE_SELで指定されたキューにデータがある事を通知
  18      STATUS            1     RW         デバイスのステータス
  19      ISR               1     RO         割り込みステータス
  20      MSI_CONFIG_VECTOR 2     RW         コントロール用キューのMSIベクタ番号
                                            （MSI有効時のみ存在）
  22      MSI_QUEUE_VECTOR  2     RW         QUEUE_SELで指定されたキューのMSIベクタ番号
                                            （MSI有効時のみ存在）

 Table: Virtio header

  offset  field name          bytes direction  description
  ------- ------------------- ----- ---------- -----------------------------------------
  0       MAC                 6     RW         MACアドレス
  6       STATUS              2	    RO        リンクアップ状態などのvirtio-net固有ステータス
  8       MAX_VIRTQUEUE_PAIRS 2	    RO        最大RX／TXキュー数（マルチキュー用）

 Table: virtio-net specific header

# Virtio PCI デバイスの初期化処理

ゲストOSにおけるVirtio PCIを用いたvirtioデバイスの初期化処理は次のようになります。

#### Step 1
通常のPCIデバイスの初期化ルーチンを実行し、Vendor ID・Device IDがvirtioのものを発見します。

#### Step 2
 デバイスのPCI I/O Spaceのマップ先アドレスを取得し、Virtio HeaderのSTATUSフィールドにACKNOWLEDGEビットをセットします(STATUSフィールドが用いるビット値は表5に記載)。

#### Step 3
Subsystem Device IDに一致するドライバをロードします。たとえばIDが1の場合はvirtio-netをロードします。

#### Step 4
ドライバがロードできたらVirtio HeaderのSTATUSフィールドにDRIVERビットをセットします。

#### Step 5
デバイス固有の初期化処理を実行します。virtio-netの場合、virtio-net specific headerからMACアドレスをコピーする、NICとしてネットワークサブシステムに登録するなどの処理が行われます。この時、Virtio HeaderのHOST_FEATURESフィールドで示されているデバイスで使える機能のうち、ドライバで使用したい機能のビットをGUEST_FEATURESへ書き込みます。FEATURESの全ビットの紹介は省略しますが、たとえばvirtio-netでChecksum Offloadingを使いたい場合はビット0、TSOv4を使いたい時はビット11を有効にする必要があります。

#### Step 6
デバイスに必要な数のキューをアロケート、Virtio Headerを通じてホストへアドレスを通知します(「キューのアロケート処理」に詳述)。

#### Step 7
ドライバの初期化処理がすべて成功したらVirtio HeaderのSTATUSフィールドにDRIVER_OKビット、途中で失敗したらFAILEDビットをセットします。

  bit   name         description
  ----- ------------ -----------------------------------
  1     ACKNOWLEDGE  ゲストOSはデバイスを発見
  2     DRIVER       ゲストOSはデバイス向けのドライバを保有
  3     DRIVER_OK    ゲストOSはドライバ初期化を完了
  7     FAILED       初期化失敗

 Table: device status

# キューのアロケート処理

「Virtio PCIデバイスの初期化処理」の第6段階で言及したキューのアロケート処理は、次のような手順をキューごとに実施する必要があります。たとえばvirtio-netの場合は3つのキューが必要なので、3回繰り返します。

#### Step 1
設定を行うキューの番号をVirtio HeaderのQUEUE_SELフィールドに書き込みます。

#### Step 2
Virtio HeaderのQUEUE_NUMフィールドを読み込みます。この値がこれから設定を行うキューのキュー長になります。値が0だった場合、ホスト側はこの番号のキューを使うことを認めていないため使用できません。

#### Step 3
キューに使うメモリ領域をアロケートします。アロケートするサイズはキュー長に合わせたサイズで、先頭アドレスはページサイズにアラインされている必要があります。

#### Step 4
メモリ領域の先頭アドレスの物理ページ番号をVirtio HeaderのQUEUE_PFNにセットします。

#### Step 5
MSI割り込みが有効な場合、Virtio HeaderのMSI_CONFIG_VECTORフィールドまたはMSI_QUEUE_VECTORフィールドに割り込みベクタ番号を書き込みます。どちらのフィールドに書き込むかはキューがコントロール用キューか否かによって異なります。

# まとめ

virtioの概要とVirtio PCIの実装について解説しました。次回はいよいよVirtqueueとこれを用いたNIC(virtio-net)の実現方法について見ていきます。

# ライセンス

Copyright (c) 2014 Takuya ASADA. 全ての原稿データ は
クリエイティブ・コモンズ 表示 - 継承 4.0 国際
ライセンスの下に提供されています。
