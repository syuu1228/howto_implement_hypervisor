---
authors:
- 'Takuya ASADA syuu@dokukino.com'
title: |
    ハイパーバイザの作り方～ちゃんと理解する仮想化技術～ 
    第１２回 virtioによる準仮想化デバイス その１「Virtqueueとvirtio-netの実現」
...

## はじめに

前回は、ゲストOSのI/Oパフォーマンスを大きく改善する「virtio」準仮想化ドライバの概要と、virtioのコンポーネントの1つである「Virtio PCI」について解説しました。今回はVirtqueueとこれを用いたNIC(virtio-net)の実現方法について見ていきます。

## virtioのおさらい

virtioは、大きく分けてVirtio PCIとVirtqueueの2つのコンポーネントからなります。Virtio PCIはゲストマシンに対してPCIデバイスとして振る舞い、次のような機能を提供します。
-デバイス初期化時のホスト<->ゲスト間ネゴシエーションや設定情報通知に使うコンフィギュレーションレジスタ
これを利用してキュー長やキュー数、キューのアドレスなどを通知する、
-割り込み(ホスト->ゲスト)、I/Oポートアクセス(ゲスト->ホスト)によるホスト<->ゲスト間イベント通知機構
-標準的なPCIデバイスのDMA機構を用いたデータ転送機能
があります。
Virtqueueはデータ転送に使われるゲストメモリ空間上のキュー構造です。デバイスごとに1つまたは複数のキューを持つことができます。たとえば、virtio-netは送信用キュー, 受信用キュー, コントロール用キューの3つを必要とします。ゲストOSは、PCIデバイスとしてvirtioデバイスを検出して初期化し、Virtqueueをデータの入出力に、割り込みとI/Oポートアクセスをイベント通知に用いてホストに対してI/Oを依頼します。本稿では、Virtqueueについてより詳しく見ていきましょう。

## Virtqueue

 Virtqueueは送受信するデータをキューイング先のDescriptorが並ぶDescriptor Table、ゲストからホストへ受け渡すdescriptorを指定するAvailable Ring、ホストからゲストへ受け渡すdescriptorを指定するUsed Ringの3つからなります(図[fig1])。
図[fig1] Virtqueueの構造
Descriptor Table, Available Ring, Used Ringのエントリ数はVirtio PCIデバイスの初期化時にVirtio headerのQUEUE_NUMへ設定した値で決められます。
 また、Virtqueueの領域はページサイズ([^1])へアラインされている必要があります。1つのVirtqueueは片方向の通信に用いられます。このため、双方向通信をサポートするには2つのVirtqueueを使用する必要があります。通信方向によって、Available RingとUsed Ringの使われ方が異なります。

[^1]: ページサイズ = 4KB

## Descriptor Table

 Descriptor TableはDescriptorがQUEUE_NUM個([^2])並んでいる配列です。Descriptorはデータ転送を行う都度動的にアロケートされるのではなく、Descriptor Table内の空きエントリを探して使用します。空きエントリを管理する構造はVirtqueue上にないため、ゲストドライバは空きDescriptorを記憶しておく必要があります(後述)。

[^2]: Virtio HeaderのQUEUE_NUMで指定する。
 Descriptorは転送するデータ1つに対して1つ使われ、データのアドレス、データ長などが含まれます(表[tab1])。
表[tab1] Descriptorの構造
データのアドレスはゲスト上の物理アドレスが用いられるため、仮想アドレス上で連続する領域でも物理ページがばらばらな場合、物理ページごとにDescriptorが1つ必要です。
このように複数のDescriptorを連続して転送したい場合には、nextで次のDescriptorの番号を指定してflagsに0x1をビットセットします。

## Indirect Descriptor

ある種のvirtioデバイスは多数のdescriptorを消費するリクエストを大量に並列に発行することにより、性能を向上させることができます。
これを可能にするのがIndirect Descriptorです。Descriptorのflagsに0x4が指定された場合、addrはIndirect Descriptor Tableのアドレスを、lenはIndirect Descriptor Tableの長さ(バイト数)を示すようになります。
 Indirect Descriptor TableはDescriptor Tableと同様、Descriptorの配列になっています。Indirect Descriptor Tableに含まれるDescriptorの数はlen/16個になります([^3])。
それぞれのデータはIndirect Descriptor Table上のDescriptorへリンクされます。

[^3]: 1つのDescriptorの長さが16bytesであるため。

## Available Ring

 Available Ringはゲストからホストへ渡したいDescriptorを指定するのに使用します(表[tab2])。ゲストはリング上の空きエントリへDescriptor番号を書き込んでidxをインクリメントします。idxは単純にインクリメントし続ける使い方が想定されているため、リング長を超えるidx値が指定された時はidxをリング長で割った余りをインデックス値として使用します。
表[tab2] Available Ringの構造
ホストは最後に処理したリング上のエントリの番号を記憶しておき(後述)、idxと比較して新しいエントリが指しているDescriptorを処理します。

## Used Ring

 Used Ringはホストからゲストへ渡したいDescriptorを指定するのに使用されます(表[tab3])。
 構造と使用方法は基本的にAvailable Ringと同じですが、リング上のエントリの構造がAvailable Ringと異なり、連続するDescriptorを先頭番号(id)と長さ(len)で範囲指定するようになっています(表[tab4])。
表[tab3] Used Ringの構造
表[tab4] Used Ringエントリの構造

## Virtqueueに含まれない変数

Virtqueueを用いてデータ転送を行うために、Virtqueueに含まれない次の変数が必要です。
+ゲストドライバ
-free_head......空きDescriptorを管理するため、空きDescriptorの先頭番号を保持
-last_used_idx......最後に処理したUsed Ring上のエントリの番号
+ホストドライバ
-last_avail_idx......最後に処理したAvailable Ring上のエントリの番号

## ゲスト->ホスト方向のデータ転送方法

 ゲストからホストへデータを転送するために、Descriptor Table, Available Ring, Used Ringをどのように使うかを次に示します(図[fig2])。
この方向のデータ転送では、Available Ringは転送データを含むDescriptorの通知に使われ、Used Ringは処理済みDescriptorの回収に使われます。

### ゲストドライバ


### 図2の番号にそって解説します。

図[fig2] ゲスト->ホスト方向データ転送のイメージ
1.ドライバの初期化時にあらかじめすべてのDescriptorのnextの値を隣り合ったDescriptorのエントリ番号に設定し空きDescriptorのチェーンを作成、チェーンの先頭Descriptorの番号をfree_headに代入しておく
2.free_headの値から空きDescriptor番号を取得
3.Descriptorのaddrにデータのアドレス、lenにデータ長を代入
4.Descriptorのnextが指す次の空きDescriptorの番号をfree_headへ代入
5.Available Ringのidxが指す空きエントリにDescriptorの番号を代入
6.Available Ringのidxをインクリメント(新しい空きエントリ)
7.Virtio HeaderのQUEUE_SELにキュー番号を書き込み
8.未処理データがあることをホストへ通知するためVirtio HeaderのQUEUE_NOTIFYへ書き込み([^4])

[^4]: QUEUE_NOTIFYへ書き込むことによりVMExitが発生し、ホスト側へ制御が移ることを意図している。

### ホストドライバ

 図[fig2]の番号にそって解説します。
9.ゲストからの通知を受けてlast_avail_idxとAvailable Ringのidxを比較、新しいエントリが指しているDescriptorを順に処理、last_avail_idxをインクリメント
10.Used Flagsのidxが指す次の空きエントリに処理済みDescriptorの番号を代入
11.Used Flagsのidxをインクリメント
12.処理が終わったことを通知するためゲストへ割り込み

### ゲストドライバ

 図[fig2]の番号にそって解説します。
13.ホストからの割り込みを受けてlast_used_idxとUsed Ringのidxを比較、新しいエントリが指している処理済みDescriptorを順に回収、last_used_idxをインクリメント
14.回収対象のDescriptorを空きDescriptorのチェーンへ戻し、free_headを更新

## ホスト->ゲスト方向のデータ転送方法

 ホストからゲストへデータを転送するために、Descriptor Table, Available Ring, Used Ringをどのように使うかを次に示します(図[fig3])。
この方向のデータ転送では、Available Ringは空きDescriptorの受け渡しに使われ、Used Ringは転送データを含むDescriptorの通知に使われます。

### ゲストドライバ

 図[fig3]の番号にそって解説します。
図[fig3] ゲスト->ホスト方向データ転送のイメージ
1.ドライバの初期化時にあらかじめすべてのDescriptorのnextの値を隣り合ったDescriptorのエントリ番号に設定し空きDescriptorのチェーンを作成、
チェーンの先頭Descriptorの番号をfree_headに代入しておく
2.Available Ringのidxが指す次の空きエントリに空きDescriptorチェーンの先頭番号を代入
3.Available Ringのidxをインクリメント
4.Virtio HeaderのQUEUE_SELにキュー番号を書き込み
5.未処理データがあることをホストへ通知するためVirtio HeaderのQUEUE_NOTIFYへ書き込み

### ホストドライバ

 図[fig3]の番号にそって解説します。
6.データ送信要求を受けてAvailable Ringを参照、必要な数のDescriptorを取り出す
7.DescriptorをAvailable Ring上の、Descriptorチェーンから切り離す
8.Descriptorのaddrにデータのアドレス、lenにデータ長を代入
9.Used Ringのidxが指す次の空きエントリにDescriptorの番号を代入
10.Used Ringのidxをインクリメント
11.未処理データがあることを通知するためゲストへ割り込み

### ゲストドライバ

 図[fig3]の番号にそって解説します。
12.ホストからの割り込みを受けてlast_used_idxとUsed Ringのidxを比較、新しいエントリが指している処理済みDescriptorを順に処理、last_used_idxをインクリメント
13.処理済みDescriptorを空きDescriptorのチェーンへ戻し、Available Ringを更新

## virtio-netの実現方法

virtio-netは受信キュー、送信キュー、コントロールキューの3つのVirtqueueからなります。
送信キューとコントロールキューはゲスト->ホスト方向のデータ転送方法で解説した手順でデータを転送します。受信キューはホスト->ゲスト方向のデータ転送方法で解説した手順でデータを転送します。受信キュー, 送信キューでは、パケットごとに1つのDescriptorを使用します。
 Descriptorのaddrには直接パケットのアドレスを指定しますが、ホストドライバからゲストドライバへいくつかの情報を通知するため、パケットの手前に専用の構造体を追加しています(表5、図[fig4])。
表[tab5] struct virtio_net_hdr
図[fig4] Descriptorに専用の構造体が付加される
 コントロールキューでは、コマンド用構造体(表6、図[fig5])にコマンド名を設定してゲストからホストへメッセージ送出します。コマンドに付属データが必要な場合は、コマンド用構造体の直後に続いてデータを配置します。コマンドはクラス(大項目)とコマンド(小項目)で整理されており、次のような種類があります。
表[tab6] struct virtio_net_ctrl_hdr
図[fig5] コマンド用構造体
VIRTIO_NET_CTRL_RXクラスは次のようなコマンドを持ち、NICのプロミスキャスモード、ブロードキャスト受信、マルチキャスト受信などの有効/無効化を行います。
-VIRTIO_NET_CTRL_RX_PROMISC
-VIRTIO_NET_CTRL_RX_ALLMULTI
-VIRTIO_NET_CTRL_RX_ALLUNI
-VIRTIO_NET_CTRL_RX_NOMULTI
-VIRTIO_NET_CTRL_RX_NOUNI
-VIRTIO_NET_CTRL_RX_NOBCAST
VIRTIO_NET_CTRL_MACクラスは次のようなコマンドを持ち、MACフィルタテーブルの設定に使用します。
-VIRTIO_NET_CTRL_MAC_TABLE_SET
-VIRTIO_NET_CTRL_MAC_ADDR_SET
VIRTIO_NET_CTRL_VLANクラスは次のようなコマンドを持ち、VLANの設定に使用します。
-VIRTIO_NET_CTRL_VLAN_ADD
-VIRTIO_NET_CTRL_VLAN_DEL
VIRTIO_NET_CTRL_ANNOUNCEクラスは次のようなコマンドを持ち、リンクステータス通知に対してackを返すのに使用します。
-VIRTIO_NET_CTRL_ANNOUNCE
-VIRTIO_NET_CTRL_ANNOUNCE_ACK
VIRTIO_NET_CTRL_MQクラスクラスは次のようなコマンドを持ち、マルチキューのコンフィギュレーションに使用します。
-VIRTIO_NET_CTRL_MQ_VQ_PAIRS_SET
-VIRTIO_NET_CTRL_MQ_VQ_PAIRS_MIN
-VIRTIO_NET_CTRL_MQ_VQ_PAIRS_MAX

## まとめ

Virtqueueと、これを用いたNIC(virtio-net)の実現方法について解説しました。次号では、これまでの総集編で、仮想化システムの全体像を振り返ります。
ライセンス
==========

Copyright (c) 2014 Takuya ASADA. 全ての原稿データ は
クリエイティブ・コモンズ 表示 - 継承 4.0 国際
ライセンスの下に提供されています。
