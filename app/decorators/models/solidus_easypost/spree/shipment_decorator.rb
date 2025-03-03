# frozen_string_literal: true

module SolidusEasypost
  module Spree
    module ShipmentDecorator
      def self.prepended(base)
        base.state_machine.before_transition(
          to: :shipped,
          do: :buy_easypost_rate,
          if: -> { SolidusEasypost.configuration.purchase_labels }
        )

        base.delegate(
          :easy_post_rate_id,
          :easy_post_shipment_id,
          to: :selected_shipping_rate,
          prefix: :selected,
          allow_nil: true,
        )
      end

      def easypost_shipment
        return unless selected_easy_post_shipment_id

        @easypost_shipment ||= SolidusEasypost.client.shipment.retrieve(selected_easy_post_shipment_id)
      end

      def easypost_postage_label_url
        easypost_shipment&.postage_label&.label_url
      end

      def select_shipping_method(shipping_method)
        # Selects the specified shipping method for the shipment.
        # This method fetches available shipping rates using the estimator and
        # marks the selected shipping rate while deselecting all others.
        estimator = ::Spree::Config.stock.estimator_class.new
        rates = estimator.shipping_rates(to_package, false)

        # Find the rate that matches the provided shipping method
        rate = rates.detect { |detected| detected.shipping_method_id == shipping_method.id }

        # Mark the selected shipping method as true and deselect others
        deselect_other_shipping_rates(rate.id)
        rate.update(selected: true)
      end

      def update_amounts
        # NOTE: Reload the shipment to reflect any updates to the selected shipping rate.
        # Updates the shipment amounts by reloading the selected shipping rate.
        # This ensures that the shipment cost is recalculated based on the latest
        # selected shipping rate.
        reload

        # Call the parent method from solidus_core to ensure proper cost recalculations.
        super
      end

      private

      def deselect_other_shipping_rates(selected_rate_id)
        # Deselects all shipping rates except the one selected by the user.
        # This ensures that only one shipping rate remains marked as selected.
        # Update all other shipping rates, setting `selected` to false.
        shipping_rates.where.not(id: selected_rate_id).update_all(selected: false)
      end

      def buy_easypost_rate
        # Skip label purchase if tracking information already exists.
        return if tracking

        easypost_shipment_id = easypost_shipment.id
        rate = easypost_shipment.rates.find do |easypost_rate|
          easypost_rate.id == selected_easy_post_rate_id
        end

        # Purchase the shipping label using the updated API syntax.
        easypost_shipment = SolidusEasypost.client.shipment.buy(
          easypost_shipment_id,
          rate: { id: rate.id }
        )

        self.tracking = easypost_shipment.tracking_code
      end

      ::Spree::Shipment.prepend self
    end
  end
end
