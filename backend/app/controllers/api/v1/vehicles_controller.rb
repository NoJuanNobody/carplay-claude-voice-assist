# frozen_string_literal: true

module Api
  module V1
    class VehiclesController < ApplicationController
      before_action :set_vehicle, only: %i[update update_state]

      # GET /api/v1/vehicles
      def index
        vehicles = current_user.vehicles.order(created_at: :desc)

        render json: {
          vehicles: vehicles.map { |v| vehicle_response(v) }
        }, status: :ok
      end

      # POST /api/v1/vehicles
      def create
        vehicle = current_user.vehicles.build(vehicle_params)
        vehicle.save!

        render json: { vehicle: vehicle_response(vehicle) }, status: :created
      end

      # PUT /api/v1/vehicles/:id
      def update
        @vehicle.update!(vehicle_params)

        render json: { vehicle: vehicle_response(@vehicle) }, status: :ok
      end

      # PUT /api/v1/vehicles/:id/state
      def update_state
        state_data = params.require(:state).permit(
          :speed, :fuel_level, :battery_level, :driving_mode, :location,
          connected_devices: []
        ).to_h

        service = VehicleContextService.new
        state = service.update_state(@vehicle.id, state_data)

        render json: { state: state }, status: :ok
      end

      private

      def set_vehicle
        @vehicle = current_user.vehicles.find(params[:id])
      end

      def vehicle_params
        params.permit(:make, :model, :year, :vin, :vehicle_type)
      end

      def vehicle_response(vehicle)
        {
          id: vehicle.id,
          make: vehicle.make,
          model: vehicle.model,
          year: vehicle.year,
          vin: vehicle.vin,
          vehicle_type: vehicle.vehicle_type,
          created_at: vehicle.created_at.iso8601
        }
      end
    end
  end
end
