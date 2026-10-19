# Sourced by the import scripts: download URL FILE fetches URL into FILE,
# when FILE exists only if the server's copy is newer. Busy or failing
# servers (429, 5xx, no answer) are asked again with truncated exponential
# backoff and jitter, as geo.admin asks
# (https://docs.geo.admin.ch/get-started/retry.html): 1, 2, 4 … 64 s plus up
# to 1 s at random, for at most 10 minutes. curl's own --retry has no jitter.
download() {
	url=$1
	file=$2
	set --
	[ -f "$file" ] && set -- -z "$file"
	delay=1
	waited=0
	while :; do
		code=$(curl -sSL -w '%{http_code}' -o "$file.part" "$@" "$url") || true
		case $code in
		304)
			rm -f "$file.part"
			return 0
			;;
		2??)
			mv "$file.part" "$file"
			return 0
			;;
		429 | 5?? | 000) ;;
		*)
			rm -f "$file.part"
			echo "$url: HTTP $code" >&2
			return 1
			;;
		esac
		if [ $((waited + delay)) -gt 600 ]; then
			rm -f "$file.part"
			echo "$url: HTTP $code, gave up after ${waited} s" >&2
			return 1
		fi
		wait=$(awk -v d="$delay" 'BEGIN { srand(); printf "%.2f", d + rand() }')
		echo "$url: HTTP $code, again in $wait s" >&2
		sleep "$wait"
		waited=$((waited + delay))
		delay=$((delay < 64 ? delay * 2 : 64))
	done
}
