#!/bin/bash

# Skrypt instalacyjny dla konfiguracji Git hooks
# Uruchamiany poprzez ./setup-hooks.sh

# Ustaw ścieżkę do hooków w konfiguracji Git
git config core.hooksPath hooks

echo "Konfiguracja Git hooks zakończona sukcesem. Hooki z katalogu 'hooks/' są teraz aktywne."
