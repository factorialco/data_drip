# frozen_string_literal: true

require "spec_helper"

RSpec.describe DataDrip::CellFanout do
  it "returns each cell's value keyed by cell id" do
    result = described_class.call(%w[a b]) { |cell_id| "value-#{cell_id}" }

    expect(result).to eq("a" => "value-a", "b" => "value-b")
  end

  it "returns an empty hash for no cells, without touching the pool" do
    expect(described_class.call([]) { raise "never called" }).to eq({})
  end

  it "reports a raised error as that cell's value instead of failing the batch" do
    result =
      described_class.call(%w[good bad]) do |cell_id|
        raise ArgumentError, "boom" if cell_id == "bad"

        :ok
      end

    expect(result["good"]).to eq(:ok)
    expect(result["bad"]).to be_a(ArgumentError)
  end

  it "distinguishes a legitimately falsy result from a failure" do
    expect(described_class.call(%w[a]) { false }).to eq("a" => false)
    expect(described_class.call(%w[a]) { nil }).to eq("a" => nil)
  end

  # The deadline is the whole point: one hung cell must cost the caller the
  # deadline once, not once per cell, and must not stall the healthy ones.
  it "shares one deadline across cells and reports the stragglers" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    result =
      described_class.call(%w[slow-1 slow-2 quick], deadline: 0.3) do |cell_id|
        sleep 5 if cell_id.start_with?("slow")
        :quick
      end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(elapsed).to be < 2
    expect(result["quick"]).to eq(:quick)
    expect(result["slow-1"]).to be_a(DataDrip::CellFanout::TimedOut)
    expect(result["slow-2"]).to be_a(DataDrip::CellFanout::TimedOut)
  end

  it "runs the cells concurrently rather than one after another" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    described_class.call(%w[a b c d], deadline: 5) { sleep 0.2 }

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.6
  end

  it "never runs more cells at once than the configured concurrency" do
    DataDrip.cell_fanout_concurrency = 3
    running = Concurrent::AtomicFixnum.new(0)
    peak = Concurrent::AtomicFixnum.new(0)

    described_class.call((1..9).map { |i| "cell-#{i}" }, deadline: 5) do
      current = running.increment
      peak.update { |seen| [ seen, current ].max }
      sleep 0.05
      running.decrement
    end

    expect(peak.value).to be <= 3
  end

  it "takes its deadline from the configuration when none is given" do
    DataDrip.cell_fanout_deadline = 0.2

    result = described_class.call(%w[slow]) { sleep 5 }

    expect(result["slow"]).to be_a(described_class::TimedOut)
  end
end
