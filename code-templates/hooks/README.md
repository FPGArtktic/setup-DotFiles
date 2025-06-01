# Git Hooks

Ten katalog zawiera hooki Git, które są używane w tym repozytorium.

## pre-push

Hook `pre-push` automatycznie wdraża stronę Hugo na serwer docelowy przed wykonaniem `git push`.

### Jak to działa

1. Buduje stronę Hugo za pomocą polecenia `hugo`
2. Czyści katalog docelowy na serwerze zdalnym
3. Kopiuje zbudowaną stronę na serwer zdalny

### Konfiguracja

Aby aktywować te hooki, wykonaj polecenie:

```bash
git config core.hooksPath hooks
```

lub uruchom skrypt:

```bash
./setup-hooks.sh
```
