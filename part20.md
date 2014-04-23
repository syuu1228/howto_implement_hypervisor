ハイパーバイザーの作り方 第２０回　bhyveにおける仮想ディスクの実装

はじめに
前回の記事では、bhyveにおける仮想NICの実装についてTAPデバイスを用いたホストドライバの実現方法を例に挙げ解説しました。
今回の記事では、bhyveにおける仮想ディスクの実装について解説していきます。

bhyveにおける仮想ディスクの実装
bhyveがゲストマシンに提供する仮想IOデバイスは、全てユーザプロセスである/usr/sbin/bhyve上に実装されています（図１）。
bhyveは実機上のディスクコントローラと異なり、ホストOSのファイルシステム上のディスクイメージファイルに対してディスクIOを行います。
これを実現するために、/usr/sbin/bhyve上の仮想ディスクコントローラは、ゲストOSからのIOリクエストをディスクイメージファイルへのファイルIOへ変換します。

以下に、ディスク読み込み手順と全体図（図１）を示します。
１，ゲストOSはvirtio-blkドライバを用いて、共有メモリ上のリングバッファにIOリクエストを書き込みます。そして、IOポートアクセスによってハイパーバイザにリクエスト送出を通知する。IOポートアクセスによってVMExitが発生し、CPUの制御がホストOSのvmm.koのコードに戻る。
bhyveの仮想ディスクコントローラのエミュレーションは、ユーザランドで行われています。vmm.koはこのVMExitを受けてioctlをreturnし/usr/sbin/bhyveへ制御を移す。
２，ioctlのreturnを受け取った/usr/sbin/bhyveは、仮想ディスクコントローラの共有メモリ上のリングバッファからリクエストを取り出します。
３，２で取り出したリクエストをパースし、ディスクイメージファイルにread()を行います。
４，読み出したデータを共有メモリ上のリングバッファに乗せ、ゲストOSに割り込みを送ります。５，ゲストOSは割り込みを受け、リングバッファからデータを読み出します。
図１，ディスク読み込み手順

書き込み処理では、リクエストと共にデータをリングバッファを用いて送りますが、それ以外は読み込みと同様です。

virtio-blkの仕組み
これまでに、準仮想化I/Oの仕組みとして、virtioとVirtqueue、virtio-netについて解説してきました。ここでは、ブロックデバイスを準仮想化する、virtio-blkについて解説を行います。
virtio-netは受信キュー、送信キュー、コントロールキューの３つのVirtqueueからなっていましたが、virtio-blkでは単一のVirtqueueを用います。これは、ディスクコントローラの挙動がNICとは異なり、必ずOSからコマンド送信を行った後にデバイスからレスポンスが返るという順序になるためです。
ブロックIOのリクエストは連載第１２回の「ゲスト→ホスト方向のデータ転送方法」で解説した手順で送信されます。
virtio-blkでは１つのブロックIOリクエストに対して、以下のようにDescriptor群を使用します。１個目のDescriptorはstruct
virtio~b~lk~o~uthdr（表１）を指します。
この構造体にはリクエストの種類、リクエスト優先度、アクセス先オフセットを指定します。２〜（ｎ−１）個目以降のDescriptorはリクエストに使用するバッファを指します。リクエストがreadな場合は読み込み結果を入れる空きバッファを、writeな場合は書き込むデータを含むバッファを指定します。
バッファのアドレスは物理アドレス指定になるため、仮想アドレスで連続した領域でも物理的配置がバラバラな状態な場合があります。これをサポートするためにバッファ用Descriptorを複数に別けて確保出来るようになっています。
struct
virtio~b~lk~o~uthdrにはバッファ長のフィールドがありませんが、これはDescriptorのlenフィールドを用いてホストへ通知されます。ｎ個目のDescriptorは1byteのステータスコード（表２）のアドレスを指します。このフィールドはホスト側がリクエストの実行結果を返すために使われます。

表１，struct virtio~b~lk~o~uthdr

表２，ステータスコード

ディスクイメージへのIO
/usr/sbin/bhyveはvirtio-blkを通じてゲストOSからディスクIOリクエストを受け取り、ディスクイメージへ読み書きを行います。bhyveが対応するディスクイメージはRAW形式のみなので、ディスクイメージへの読み書きはとても単純です。ゲストOSから指定されたオフセット値とバッファ長をそのまま用いてディスクイメージへ読み書きを行えばよいだけです。
それでは、このディスクイメージへのIOの部分についてbhyveのコードを実際に確認してみましょう。/usr/sbin/bhyveの仮想ディスクIO処理のコードをコードリスト１に示します。

/\* ゲストOSからIO要求があった時に呼ばれる \*/ static void
pci~v~tblk~p~roc(struct pci~v~tblk~s~oftc \*sc, struct vqueue~i~nfo
\*vq)

struct virtio~b~lk~h~dr \*vbh; uint8~t~ \*status; int i, n; int err; int
iolen; int writeop, type; off~t~ offset; struct iovec iov[VTBLK~M~AXSEGS
+ 2]; uint16~t~ flags[VTBLK~M~AXSEGS + 2]; /\*
iovに１リクエスト分のDescriptorを取り出し \*/ n = vq~g~etchain(vq, iov,
VTBLK~M~AXSEGS + 2, flags); 〜 略 〜  /\* 一つ目のDescriptorはstruct
virtio~b~lk~o~uthdr \*/ vbh = iov[0].iov~b~ase;  /\*
最後のDescriptorはステータスコード \*/ status = iov[–n].iov~b~ase; 〜 略
〜 /\* リクエストの種類 \*/  type = vbh-\>vbh~t~ype; writeop = (type ==
VBH~O~P~W~RITE); /\* オフセットをsectorからbyteに変換 \*/ offset =
vbh-\>vbh~s~ector \* DEV~B~SIZE; /\* バッファの合計長 \*/ iolen = 0; for
(i = 1; i \< n; i++) <span> 〜 略 〜 iolen += iov[i].iov~l~en; </span>
〜 略 〜 switch (type) <span> /\*
WRITEならpwritev()でiovの配列で表されるバッファリストからディスクイメージへ書き込み
\*/ case VBH~O~P~W~RITE: err = pwritev(sc-\>vbsc~f~d, iov + 1, i - 1,
offset); break; /\*
READならpreadv()でディスクイメージからiovの配列で表されるバッファリストへ読み込み
\*/ case VBH~O~P~R~EAD: err = preadv(sc-\>vbsc~f~d, iov + 1, i - 1,
offset); break; /\* IDENTなら仮想ディスクのidentifyを返す \*/ case
VBH~O~P~I~DENT: /\* Assume a single buffer \*/ strlcpy(iov[1].iov~b~ase,
sc-\>vbsc~i~dent, min(iov[1].iov~l~en, sizeof(sc-\>vbsc~i~dent))); err =
0; break; default: err = -ENOSYS; break; </span> 〜 略 〜 /\*
ステータスコードのアドレスにIOの結果を書き込む \*/ if (err \< 0) <span>
if (err == -ENOSYS) \*status = VTBLK~SU~NSUPP; else \*status =
VTBLK~SI~OERR; </span> else \*status = VTBLK~SO~K;

〜 略 〜 /\* ステータスコードを書き込んだ事を通知 \*/ vq~r~elchain(vq,
1);

コードリスト１，/usr/sbin/bhyveの仮想ディスクIO処理

まとめ 今回は仮想マシンのストレージデバイスについて解説しました。
次回は、仮想マシンのコンソールデバイスについて解説します。￼
NICではOSから何もリクエストを送らなくてもネットワーク上の他のノードからパケットが届くのでデータが送られてきます。このため、必ずOSからリクエストを送ってから届くというような処理にはなりません。￼
Virtqueue上でデータ転送をおこなうための構造体。第１２回のVirtqueueの項目を参照。￼
QCOW2形式などのより複雑なフォーマットでは未使用領域を圧縮するため、ゲスト・ホスト間でオフセット値が一致しなくなり、またメタデータを持つ必要が出てくるのでRAWイメージと比較して複雑な実装になります。
