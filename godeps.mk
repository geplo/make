## godeps.mk is a helper to update the Godeps directory.
##
## Targets:
##  - update_godeps:       run godep save ./...
##  - update_godeps_local: run godeps save .
##  - godeps_clean

BACKUP          = /tmp/.$(NAME)_Godeps.bak

update_godeps_local: godeps_clean
		@godep save .

update_godeps   :
		@rm -rf $(BACKUP)
		@[ -d Godeps ] && mv Godeps $(BACKUP) || true
		@godep save ./... || ([ -d $(BACKUP) ] && mv $(BACKUP) Godeps; exit 1)
		@rm -rf $(BACKUP)

clean           : godeps_clean
godeps_clean    :
		@rm -rf .Godeps.bak

.PHONY          : update_godeps update_godeps_local godeps_clean
