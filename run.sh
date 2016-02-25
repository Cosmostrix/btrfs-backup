#!/bin/zsh -p

set -ue -o pipefail

function pubsubsync() {
	local pub_repo=$1 pub_name=$2 pub_src=$3 sub_repo=$4 sub_name=$5 time=$6
	create_snapshot $pub_repo/$pub_name $pub_src $time
	detect_parent $pub_repo $pub_name $sub_repo $sub_name
	if [ $OPTS ] || confirm_fullbackup; then
		btrfs_sync "$OPTS" $pub_repo $pub_name $sub_repo $sub_name $time
	fi
}

function create_snapshot() {
	local snapshot_dir=$1 src_subvolume=$2 time=$3
	local snapshot=$snapshot_dir/$time
	[ -d $snapshot ] && return
	echo "(1/3) バックアップ対象のスナップショットを作成します"
	# echo "\tsnapshot $src_subvolume -> $snapshot"
	mkdir -p $snapshot_dir
	btrfs subvolume snapshot -r $src_subvolume $snapshot
	reln $time $snapshot_dir/latest || true
}

# シンボリックリンクを作成/置き換えする。その他のファイルは念の為削除しない。
# 元のリンク先が切れていない場合その絶対パスを出力する。
function reln() {
	[ -e $2 -a ! -L $2 ] && (echo "エラー: 非シンボリックリンク: $2"; false)
	if readlink -e $2; then
		ln -sfn $1 $2; true
	else
		ln -sfn $1 $2; false
	fi
}

# 前回のバックアップがあるなら差分に使う
function detect_parent() {
	local pub_repo=$1 pub_name=$2 sub_repo=$3 sub_name=$4
	OPTS=""
	if prev_shot=`readlink -e $pub_repo/$pub_name/$sub_name`; then
		# mtime && subvol list 使った方が確実？
		prev_id=$(basename $prev_shot)
		if [ -d $sub_repo/$pub_name/$prev_id ]; then
			OPTS="-p$prev_shot"
			echo "増分バックアップします: $prev_id"
		else
			echo "警告: $prev_shot に対応する転送先のバックアップが見つかりませんでした"
		fi
	fi
}

function confirm_fullbackup() {
	echo "最初のバックアップには時間がかかります。続行しますか？(y/N)"
	read -q
}

function btrfs_sync() {
	local opts=$1 pub_repo=$2 pub_name=$3 sub_repo=$4 sub_name=$5 time=$6
	echo "(2/3) バックアップ転送"
	mkdir -p $sub_repo/$pub_name
	echo "btrfs send $opts $pub_repo/$pub_name/$time | btrfs receive -vv $sub_repo/$pub_name"
	btrfs send $opts $pub_repo/$pub_name/$time | btrfs receive -vv $sub_repo/$pub_name

	echo "(2.5/3) 手元のバックアップ情報を更新"
	if subvol=`reln $time $pub_repo/$pub_name/$sub_name`; then
		echo \t$ btrfs subvolume delete $subvol
		confirm_delete $subvol && btrfs subvolume delete $subvol
	fi

	echo "(3/3) バックアップ先の情報を更新"
	if subvol=`reln $time $sub_repo/$pub_name/latest`; then
		echo \t$ btrfs subvolume delete $subvol
		confirm_delete $subvol && btrfs subvolume delete $subvol
	fi
}

function confirm_delete() {
	echo "以前のバックアップ $1 を削除しますか？(y/N)"
	echo "注意: "
	read -q
}

function main() {
	source btrfs_backup.conf_
	#echo Search Path: $REPO_PATH
	REPO_PATH=(${(@f)"$(readlink -e $REPO_PATH || true)"})
	echo ">>> Repositories Found: $REPO_PATH"

	for x in $REPO_PATH; do
		unset name pub sub
		repo=$x source $x/.repoconfig
		pub_name=$name pub_src=${pub:-}
		echo ">>> Sync Repository: $pub_name [pub $pub_src] [sub ${sub:-()}]"
		time=test$(date "+%y%m%d-%H%M%S")
		if [ ${+pub} ]; then
			for y in $REPO_PATH; do
				unset name pub sub
				repo=$y source $y/.repoconfig
				sub=${sub:-()}
				# echo env $name, ${pub:-}, $sub
				if (( ${sub[(I)$pub_name]} )); then
					echo ">>> Sending: $pub_name -> $name"
					pubsubsync $x $pub_name $pub_src $y $name $time
				fi
			done
		else
			echo "Note: sub-sub backup not supported. skip."
		fi
	done
}
main
