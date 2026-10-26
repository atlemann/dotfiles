# Public login keys of the main user, one per machine, keyed by hostname.
# Private keys are never stored here; generate one per machine with
#   ssh-keygen -t ed25519 -C "$USER@$(hostname)"
# Each host trusts every key in this set except its own.
{
  # aru-ws = "ssh-ed25519 AAAA... aru@aru-ws";
  # aru-lws = "ssh-ed25519 AAAA... aru@aru-lws";
  # woody = "ssh-ed25519 AAAA... aru@woody";
}
