# Contributing

Contributions are welcome! This project is licensed under GPL v3.

## How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Test locally (`sudo make build && make test`)
5. Commit with a descriptive message
6. Push to your fork and open a Pull Request

## Development Setup

```bash
git clone https://github.com/RafaelKa/victron-venus-os-in-docker.git
cd victron-venus-os-in-docker

# Build and test
sudo make build MACHINE=raspberrypi5
make test
```

## Code Style

- Shell scripts: use `bash` with `set -euo pipefail`
- Include SPDX license headers in all files
- Use meaningful variable names and add comments for non-obvious logic

## Reporting Issues

Please include:
- Your host OS and architecture
- Docker version (`docker --version`)
- The Venus OS image version/feed you're using
- Container logs (`docker logs venus-os`)
- Service status (`docker exec venus-os sh -c 'svstat /service/*'`)
