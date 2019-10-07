# frozen_string_literal: true

require 'options'

RSpec.describe Options do
  let(:aliases) { { f: :flag } }
  it 'empty' do
    expect(described_class.parse).to be_nil
  end
  it 'literal' do
    expect(described_class.parse('f')).to match(prologue: ['f'])
  end
  it 'literals' do
    expect(described_class.parse('f', '--', '-f')).to match(
      prologue: ['f'],
      epilogue: ['-f']
    )
  end
  it 'flag' do
    expect(described_class.parse('-f')).to match(flags: { f: true })
    expect(described_class.parse('-f', '-f')).to match(flags: { f: 2 })
  end
  it 'long-flag' do
    expect(described_class.parse('--flag')).to match(flags: { flag: true })
    expect(described_class.parse(:flag)).to match(flags: { flag: true })
    expect(described_class.parse('--flag', '--flag')).to match(flags: { flag: 2 })
    expect(described_class.parse(:flag, :flag)).to match(flags: { flag: 2 })
  end
  it 'inversion' do
    expect(described_class.parse('--no-flag')).to match(flags: { flag: false })
    expect(described_class.parse(:no_flag)).to match(flags: { flag: false })
    expect(described_class.parse('--flag', '--no-flag')).to match(flags: { flag: false })
    expect(described_class.parse(:flag, :no_flag)).to match(flags: { flag: false })
    expect(described_class.parse('--flag', '--no-flag', '--no-flag')).to match(flags: { flag: false })
    expect(described_class.parse(:flag, :no_flag, :no_flag)).to match(flags: { flag: false })
    expect(described_class.parse('--no-flag', '--flag', '--no-flag')).to match(flags: { flag: false })
    expect(described_class.parse(:no_flag, :flag, :no_flag)).to match(flags: { flag: false })
  end
  it 'alias' do
    expect(described_class.parse('-f', aliases: aliases)).to match(flags: { flag: true })
    expect(described_class.parse('-f', '-f', aliases: aliases)).to match(flags: { flag: 2 })
    expect(described_class.parse('--flag', '-f', aliases: aliases)).to match(flags: { flag: 2 })
  end
  context 'error conditions' do
    it 'flag after value' do
      expect { described_class.parse('--flag=x', '--flag', '--no-flag') }.to raise_error(/missing value.*'--flag'/i)
      expect { described_class.parse('--flag=example-value', '-f', aliases: aliases) }.to raise_error(/boolean.*'-f'.*"example-value"/i)
      expect { described_class.parse('--flag=example-value', '--flag') }.to raise_error(/missing value.*'--flag'/i)
    end
  end
end
