#!/usr/bin/env bash

# ----------------------------------------------------------------------- #
# The tmux half of `smart-splits-backend-tmux`, for TPM.                    #
#                                                                           #
#   set -g @plugin 'smart-splits-nvim/backend-tmux'                         #
#                                                                           #
# Binds the movement and resize keys so that a pane running Neovim is sent  #
# the key, and any other pane is acted on here. Which is which comes from   #
# `@pane-is-vim`, a pane-local option the Neovim half of this plugin sets   #
# while Neovim owns the pane.                                               #
#                                                                           #
# Every option below is optional; the defaults match smart-splits.nvim's    #
# own, so the two halves agree without configuring either.                  #
# ----------------------------------------------------------------------- #

set -euo pipefail

get_option() {
  local value
  value="$(tmux show-options -gqv "$1")"
  echo "${value:-$2}"
}

# What to do when the pane is against the edge of its tmux window, matching
# smart-splits.nvim's `move.at_edge`. Keep the two in step: the Neovim half
# applies the same policy from inside Neovim, and disagreeing halves make
# navigation depend on what happens to be running in the pane.
#   wrap  => focus the pane on the far side (tmux's own behaviour)
#   stop  => do nothing
#   split => create a pane, inheriting the current pane's directory
at_edge="$(get_option '@smart-splits_at_edge' 'wrap')"

move_left_key="$(get_option '@smart-splits_move_left_key' 'C-h')"
move_down_key="$(get_option '@smart-splits_move_down_key' 'C-j')"
move_up_key="$(get_option '@smart-splits_move_up_key' 'C-k')"
move_right_key="$(get_option '@smart-splits_move_right_key' 'C-l')"

resize_left_key="$(get_option '@smart-splits_resize_left_key' 'M-h')"
resize_down_key="$(get_option '@smart-splits_resize_down_key' 'M-j')"
resize_up_key="$(get_option '@smart-splits_resize_up_key' 'M-k')"
resize_right_key="$(get_option '@smart-splits_resize_right_key' 'M-l')"

resize_step_size="$(get_option '@smart-splits_resize_step_size' '3')"

# Bind one direction, given its keys and the tmux vocabulary for it: the
# `select-pane`/`resize-pane` flag, the `#{pane_at_*}` variable that answers
# "is there a pane that way?", and the `split-window` flags that make one.
setup_direction() {
  local move_key="$1" resize_key="$2" flag="$3" edge="$4" split_flags="$5"
  local fallback copy_mode

  case "$at_edge" in
    stop)
      fallback="if -F '#{$edge}' '' 'select-pane -$flag'"
      copy_mode="$fallback"
      ;;
    split)
      fallback="if -F '#{$edge}' 'split-window $split_flags -c \"#{pane_current_path}\"' 'select-pane -$flag'"
      # copy mode is for reading, not for rearranging: splitting would drop out
      # of it, so the edge is where movement stops
      copy_mode="if -F '#{$edge}' '' 'select-pane -$flag'"
      ;;
    *)
      fallback="select-pane -$flag"
      copy_mode="$fallback"
      ;;
  esac

  tmux bind-key -n "$move_key" if -F '#{@pane-is-vim}' "send-keys $move_key" "$fallback"
  tmux bind-key -n "$resize_key" if -F '#{@pane-is-vim}' "send-keys $resize_key" \
    "resize-pane -$flag $resize_step_size"
  tmux bind-key -T copy-mode-vi "$move_key" "$copy_mode"
}

main() {
  if [ "$at_edge" != 'wrap' ] && [ "$at_edge" != 'stop' ] && [ "$at_edge" != 'split' ]; then
    tmux display-message "smart-splits: @smart-splits_at_edge must be wrap, stop or split, got '$at_edge'"
    at_edge='wrap'
  fi

  setup_direction "$move_left_key" "$resize_left_key" L pane_at_left -hb
  setup_direction "$move_down_key" "$resize_down_key" D pane_at_bottom -v
  setup_direction "$move_up_key" "$resize_up_key" U pane_at_top -vb
  setup_direction "$move_right_key" "$resize_right_key" R pane_at_right -h
}

main
