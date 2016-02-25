#!/bin/zsh
BTRFS=btrfs

# 存在確認 * 正規化
src=$(readlink -e ${SOURCE_DIR:-/})
ssdir=$(readlink -e $src/${SNAPSHOT_DIR_NAME:-backup})
BACKUP_DIR=$(readlink -e $(dirname $0)/..)
BACKUP_TAG=backup_2

backup_name=$(date "+%y%m%d-%H%M%S")
snapshot=$ssdir/$backup_name

set -ue -o pipefail

# シンボリックリンクを作成/置き換えする。その他のファイルは念の為削除しない。
# 元のリンク先が切れていない場合その絶対パスを出力する。
function reln() {
	[ -e $2 ] && [ -L $2 ] || (echo "エラー: 非シンボリックリンク: $2"; false)
	readlink -e $2 || true
	ln -sfn $1 $2
}

function confirm() {
	echo "以前のバックアップ $1 を削除しますか？(y/N)"
	read -q
}

echo "$src → $BACKUP_DIR/$backup_name"
echo "バックアップ対象(手元)のスナップショットを作成します\n\t$src → $snapshot"
mkdir -p $ssdir
btrfs subvolume snapshot -r $src $snapshot
reln $backup_name $ssdir/latest_snapshot

# 前回のバックアップがあるなら差分に使う
incremental=""
if prev_shot=`readlink -e $ssdir/$BACKUP_TAG`; then
	# mtime && subvol list 使った方が確実？
	prev_name=$(basename $prev_shot)
	if [ -d $BACKUP_DIR/$prev_name ]; then
		incremental="-p$prev_shot"
		echo "増分バックアップします: $prev_name → $backup_name"
	else
		echo "警告: $prev_shot に対応する転送先のバックアップが見つかりませんでした"
	fi
else
	echo "初回のバックアップには時間がかかります"
fi

# バックアップ転送
echo "$BTRFS send $incremental $snapshot | $BTRFS receive -vv $BACKUP_DIR"
$BTRFS send $incremental $snapshot | $BTRFS receive -vv $BACKUP_DIR

echo "手元のバックアップ情報を更新"
if subvol=`reln $backup_name $ssdir/$BACKUP_TAG`; then
	confirm $subvol && $BTRFS subvolume delete $subvol
fi

echo "バックアップ先の情報を更新"
if subvol=`reln $backup_name $BACKUP_DIR/$BACKUP_TAG`; then
	confirm $subvol && $BTRFS subvolume delete $subvol
fi

