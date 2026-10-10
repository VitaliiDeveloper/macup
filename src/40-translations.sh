# ---------------------------------------------------------------- translations
# Format: English text || translation. Keep every %s / %d in the same order.
lang_table(){
  case "$1" in
  uk) cat <<'EOF'
@include i18n/uk.txt
EOF
  ;;
  ru) cat <<'EOF'
@include i18n/ru.txt
EOF
  ;;
  esac
}

load_lang

