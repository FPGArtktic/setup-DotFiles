# Histfile
HISTSIZE=-1        # Nieograniczona liczba linii w historii
HISTFILESIZE=-1     # Nieograniczona wielkość pliku historii
HISTTIMEFORMAT="%F %T " # Opcjonalnie: Dodaje znacznik czasu do każdej komendy w historii (YYYY-MM-DD HH:MM:SS)
PROMPT_COMMAND="history -a" # Dodaje komendy do pliku historii po każdym poleceniu
shopt -s histappend # Dodaje nowe komendy do pliku historii, zamiast go nadpisywać
shopt -s checkwinsize # Zmienia rozmiar okna terminala, aktualizuje historię


git_branch () { git branch 2> /dev/null | sed -e "/^[^*]/d" -e "s/* \(.*\)/\1/"; }
HOST='\033[02;36m\]\h'; HOST=' '$HOST
TIME='\033[01;31m\]\t \033[01;32m\]'
LOCATION='\[\033[01;33m\]`pwd | sed "s#\(/[^/]\{1,\}/[^/]\{1,\}/[^/]\{1,\}/\).*\(/[^/]\{1,\}/[^/]\{1,\}\)/\{0,1\}#\1_\2#g"`\[\033[00m\]'
BRANCH=' \033[00;33m\]$(git_branch)\[\033[00m\]\n$ '
if [ -z "$USER" ]; then
  USER="root"
fi
PS1=$TIME$USER$HOST$LOCATION$BRANCH
PS2='\[\033[01;36m\]>'

alias cp='rsync -avh --progress'
