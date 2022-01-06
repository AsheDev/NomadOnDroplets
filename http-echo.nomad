job "http-echo" {
  datacenters = ["dc1"]
  group "echo" {
    count = 5
        network {
	  mode = "bridge"
          port "http" {
	    #static = 9001
          }
        }

    service {
      name = "http-listener"
      port = "http"
      tags = [
        "traefik.enable=true",
        # https://doc.traefik.io/traefik/v1.5/basics/#frontends
        # Note the Path is using backticks!
        "traefik.http.routers.http.rule=Path(`/listener`)"
      ]
    }

    task "web" {
      driver = "docker"
      config {
        image = "hashicorp/http-echo:latest"
        args  = [
          "-listen", ":${NOMAD_PORT_http}",
          "-text", "You've found allocation ${NOMAD_ALLOC_ID}, good job!",
        ]
      }
      resources {
	cpu = 32
	memory = 12
      }
    }
  }
}
