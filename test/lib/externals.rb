# frozen_string_literal: true

require_relative "../../lib/spiseq/external/sonic_pi"

# Sonic Pi imports only for tests.

module SpiSeq
  module External
    module Enumerables
      def self.ring(*args)
        SonicPi.spi_call(:ring, *args)
      end
    end

    module Theory
      def self.chord(root, name, **kwargs)
        SonicPi.spi_call(:chord, root, name, **kwargs)
      end

      def self.chord_names
        SonicPi.spi_call(:chord_names)
      end

      def self.chord_degree(degree, tonic, scale_name, n, **kwargs)
        SonicPi.spi_call(:chord_degree, degree, tonic, scale_name, n, **kwargs)
      end

      def self.degree(degree, root, scale_name)
        SonicPi.spi_call(:degree, degree, root, scale_name)
      end

      def self.scale(tonic, name, num_octaves: 1)
        SonicPi.spi_call(:scale, tonic, name, num_octaves: num_octaves)
      end
    end

    module Random
      def self.use_random_seed(seed)
        SonicPi.spi_call(:use_random_seed, seed)
      end
    end
  end
end
