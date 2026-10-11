# ---------------------------------------------------------------- translations
# Format: English text || translation. Keep every %s / %d in the same order.
lang_table(){
  case "$1" in
  uk) cat <<'EOF'
@i18n uk
EOF
  ;;
  ru) cat <<'EOF'
@i18n ru
EOF
  ;;
  esac
}

load_lang

