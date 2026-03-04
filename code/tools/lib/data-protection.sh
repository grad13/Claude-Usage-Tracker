#!/bin/bash
# データ保護関数: build-and-install.sh と test-build-install.sh の両方が source する
#
# 使い方:
#   source "$(dirname "$0")/lib/data-protection.sh"
#   snapshot_file "/path/to/file.json"    # テスト前にハッシュ記録 + .backup 作成
#   restore_file_if_changed "/path/to/file.json"  # テスト後に変更検出 → リストア

# ファイルの SHA-256 ハッシュを記録し、.backup にコピーする。
# ファイルが存在しない場合はスキップ。
# ハッシュは _SNAPSHOT_HASH_<ファイル名のサニタイズ> 変数に保存される。
snapshot_file() {
    local file="$1"
    local key
    key=$(_sanitize_key "$file")

    if [ -f "$file" ]; then
        local hash
        hash=$(shasum -a 256 "$file" | cut -d' ' -f1)
        eval "_SNAPSHOT_HASH_${key}='${hash}'"
        cp "$file" "${file}.backup"
    else
        eval "_SNAPSHOT_HASH_${key}=''"
    fi
}

# テスト後にファイルが変更・削除されていないか検証し、必要ならリストアする。
# 戻り値: 0=変更なし/スキップ, 1=リストアした, 2=削除からリストアした
restore_file_if_changed() {
    local file="$1"
    local key
    key=$(_sanitize_key "$file")

    local hash_before
    eval "hash_before=\${_SNAPSHOT_HASH_${key}:-}"

    # snapshot 時にファイルが存在しなかった → スキップ
    if [ -z "$hash_before" ]; then
        return 0
    fi

    if [ -f "$file" ]; then
        local hash_after
        hash_after=$(shasum -a 256 "$file" | cut -d' ' -f1)
        if [ "$hash_before" != "$hash_after" ]; then
            echo "WARNING: Tests corrupted $(basename "$file") — restoring from backup."
            cp "${file}.backup" "$file"
            rm -f "${file}.backup"
            return 1
        fi
        rm -f "${file}.backup"
        return 0
    else
        echo "WARNING: Tests deleted $(basename "$file") — restoring from backup."
        cp "${file}.backup" "$file"
        rm -f "${file}.backup"
        return 2
    fi
}

# 内部: ファイルパスを変数名に使えるキーに変換
_sanitize_key() {
    echo "$1" | sed 's/[^a-zA-Z0-9]/_/g'
}
