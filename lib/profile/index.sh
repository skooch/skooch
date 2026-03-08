# Profile system entry point
# Sources all modules in dependency order.

# Use DOTFILES_DIR if set, otherwise derive from this script's location
_PROFILE_LIB_DIR="${DOTFILES_DIR:-$HOME/projects/skooch}/lib/profile"

source "$_PROFILE_LIB_DIR/init.sh"
source "$_PROFILE_LIB_DIR/helpers.sh"
source "$_PROFILE_LIB_DIR/snapshot.sh"
source "$_PROFILE_LIB_DIR/apply.sh"
source "$_PROFILE_LIB_DIR/sync.sh"
source "$_PROFILE_LIB_DIR/diff.sh"
source "$_PROFILE_LIB_DIR/main.sh"
