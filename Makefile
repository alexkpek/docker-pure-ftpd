ifeq ('$(origin SUDO)', 'command line')
SUDO_MODE = $(SUDO)
endif
ifeq ($(SUDO_MODE),1)
	S = $(S)
else
	S =  
endif
.PHONY: test test-tls build run run-tls kill enter setup-bob test-bob push pull

test: build run logs-for-5 setup-bob test-bob

test-tls: build run-tls logs-for-5 test-bob-tls

# tail logs for a set number of seconds
logs-for-%:
	@echo "-----"
	@echo "watching logs for next $* seconds"
	@echo "-----"
	-timeout -s9 $* $(S)docker logs -f ftpd_server

build:
	$(S)docker build --rm -t stilliard/pure-ftpd:bmcclure .

run: kill
	$(S)docker run -d --name ftpd_server -p 21:21 -p 30000-30009:30000-30009 -e "PUBLICHOST=localhost" -e "ADDED_FLAGS=-d -d" pure-ftp-demo

# runs with auto generated tls cert & creates test bob user
run-tls: kill
	-$(S)docker volume rm ftp_tls
	$(S)docker volume create --name ftp_tls
	$(S)docker run -d --name ftpd_server -p 21:21 -p 30000-30009:30000-30009 -e "PUBLICHOST=localhost" -e "ADDED_FLAGS=-d -d --tls 2" -e "TLS_CN=localhost" -e "TLS_ORG=Demo" -e "TLS_C=UK" -e"TLS_USE_DSAPRAM=true" -e FTP_USER_NAME=bob -e FTP_USER_PASS=test -e FTP_USER_HOME=/home/ftpusers/bob -v ftp_tls:/etc/ssl/private/ pure-ftp-demo

kill:
	-$(S)docker kill ftpd_server
	-$(S)docker rm ftpd_server

enter:
	$(S)docker exec -it ftpd_server sh -c "export TERM=xterm && bash"

# Setup test "bob" user with "test" as password
setup-bob:
	$(S)docker exec -it ftpd_server sh -c "(echo test; echo test) | pure-pw useradd bob -f /etc/pure-ftpd/passwd/pureftpd.passwd -m -u ftpuser -d /home/ftpusers/bob"
	@echo "User bob setup with password: test"

# simple test to list files, upload a file, download it to a new name, delete it via ftp and read the new local one to make sure it's in tact
test-bob:
	echo "Test file was read successfully!" > test-orig-file.txt
	echo "user bob test\n\
	ls -alh\n\
	put test-orig-file.txt\n\
	ls -alh\n\
	get test-orig-file.txt test-new-file.txt\n\
	delete test-orig-file.txt\n\
	ls -alh" | ftp -n -v -p localhost 21
	cat test-new-file.txt
	rm test-orig-file.txt test-new-file.txt

# test again but with tls (uses lftp for tls support)
test-bob-tls:
	echo "Test file was read successfully!" > test-orig-file.txt
	cert="$$($(S)docker volume inspect --format '{{ .Mountpoint }}' ftp_tls)/pure-ftpd.pem";\
	echo "ls -alh\n\
	put test-orig-file.txt\n\
	echo '~ uploaded file ~'\n\
	ls -alh\n\
	get test-orig-file.txt -o test-new-file.txt\n\
	rm test-orig-file.txt\n\
	echo '~ removed file ~'\n\
	ls -alh" | $(S)lftp -u bob,test -e "set ssl:ca-file '$$cert'" localhost 21
	cat test-new-file.txt
	$(S)rm test-orig-file.txt test-new-file.txt

# git commands for quick chaining of make commands
push:
	git push --all
	git push --tags

pull:
	git pull
