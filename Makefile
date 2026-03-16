.PHONY: setup backend-setup ios-build ios-test backend-test docker-up docker-down

setup: backend-setup ios-build
	@echo "Setup complete."

backend-setup:
	cd backend && bundle install
	cd backend && bin/rails db:prepare

ios-build:
	cd ios/CarPlayAssistant && swift build

ios-test:
	cd ios/CarPlayAssistant && swift test

backend-test:
	cd backend && bundle exec rspec

docker-up:
	docker compose up -d

docker-down:
	docker compose down
