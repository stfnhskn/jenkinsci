

& docker network create jenkins | Out-Host
# & docker  network ls --format '{{json . }}' | jq .

$arguments = @(
    'run',
    '--name', 'jenkins-docker',
    '--rm',
    '--detach',
    '--privileged'
    '--network', 'jenkins',
    '--network-alias','docker',
    '--env','DOCKER_TLS_CERTDIR=/certs',
    '--volume','jenkins-docker-certs:/certs/client',
    '--volume','jenkins-data:/var/jenkins_home',
    'docker:dind'
)
& docker $arguments

& docker build -t myjenkins:1.0 .

$arguments_jenkins = @(
    'run',
    '--name', 'jenkins',
    '--rm',
    '--detach',
    '--network', 'jenkins',
    '--env','DOCKER_HOST=tcp://docker:2376',
    '--env', 'DOCKER_CERT_PATH=/certs/client',
    '--env', 'DOCKER_TLS_VERIFY=1'
    '--volume','jenkins-data:/var/jenkins_home',
    '--volume','jenkins-docker-certs:/certs/client:ro',
    '--publish', '8080:8080',
    '--publish', '50000:50000',
    'myjenkins:1.0.0'
)

& docker $arguments_jenkins

$arguments_gitlab = @(
    'run',
    '--name', 'gitlab',
    '--detach',
    '--network', 'jenkins',
    '--restart', 'always',
    '--env','DOCKER_HOST=tcp://docker:2376',
    '--env', 'DOCKER_CERT_PATH=/certs/client',
    '--env', 'DOCKER_TLS_VERIFY=1'
    '--volume','gitlab-config:/etc/gitlab',
    '--volume','gitlab-logs:/var/log/gitlab',
    '--volume','gitlab-data:/var/opt/gitlab',
    '--publish', '9443:443',
    '--publish', '9080:80',
    '--publish', '9022:22',
    'gitlab/gitlab-ce:14.1.2-ce.0'
)
& docker $arguments_gitlab