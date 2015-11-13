///<reference path="../typings/react/react.d.ts"/>
///<reference path="../typings/react-dom/react-dom.d.ts"/>

/* @flow */

"use strict";

import * as xp_common from './common.tsx';
import * as xp_utils from './utils.ts';
import * as xp_charts from './charts.tsx';
import * as Database from './database.ts';
import React = require ('react');
import ReactDOM = require ('react-dom');

interface SelectionNames {
	machineName: string;
	configNameConc: string;
	configNameSeq: string;
	benchmark: string;
}

class Controller {
	private initialSelectionNames: SelectionNames;
	private initialPercentile: number;

	constructor (benchmark: string, percentile: number) {
		const machineName = 'benchmarker';
		const configNameConc = 'auto-sgen-conc-noturbo-binary';
		const configNameSeq = 'auto-sgen-noturbo-binary';
		this.initialSelectionNames = {
			machineName: machineName,
			configNameConc: configNameConc,
			configNameSeq: configNameSeq,
			benchmark: benchmark === undefined ? 'graph4' : benchmark
		};
		this.initialPercentile = percentile === undefined ? 0.5 : percentile;
	}

	public loadAsync () : void {
		this.checkAllDataLoaded ();
	}

	private checkAllDataLoaded () : void {
		this.allDataLoaded ();
	}

	private allDataLoaded () : void {
		ReactDOM.render (<Page
					initialSelectionNames={this.initialSelectionNames}
					initialPercentile={this.initialPercentile}
					onChange={(selectionNames: SelectionNames, percentile: number) => this.onChange (selectionNames, percentile)} />,
			document.getElementById ('pauseTimesPage')
		);

		this.onChange (this.initialSelectionNames, this.initialPercentile);
	}

	private onChange (selectionNames: SelectionNames, percentile: number) : void {
		xp_common.setLocationForDict ({ benchmark: selectionNames.benchmark, percentile: percentile });
	}
}

interface PageProps {
	initialSelectionNames: SelectionNames;
	initialPercentile: number;
	onChange: (selectionNames: SelectionNames, percentile: number) => void;
}

interface PageState {
	benchmarks: Array<string>;
	selectionNames: SelectionNames;
	sortedResultsConc: Array<Database.ArrayResults>;
	sortedResultsSeq: Array<Database.ArrayResults>;
	percentile: number;
}

class Page extends React.Component<PageProps, PageState> {
	constructor (props: PageProps) {
		super (props);
		this.state = {
			selectionNames: this.props.initialSelectionNames,
			benchmarks: undefined,
			sortedResultsConc: [],
			sortedResultsSeq: [],
			percentile: this.props.initialPercentile
		};
	}

	public componentWillMount () : void {
		Database.fetchResultArrayBenchmarks (this.state.selectionNames.machineName,
			this.state.selectionNames.configNameConc,
			'pause-times',
			(benchmarks: Array<string>) => {
				this.setState ({ benchmarks: benchmarks } as any);
			}, (error: Object) => {
				alert ("error loading benchmark names: " + error.toString ());
			});

		this.fetchResults (this.state.selectionNames, true);
		this.fetchResults (this.state.selectionNames, false);
	}

	private fetchResults (selectionNames: SelectionNames, conc: boolean) : void {
		const configName = conc ? selectionNames.configNameConc : selectionNames.configNameSeq;
		Database.fetchResultArrays (selectionNames.machineName, configName, selectionNames.benchmark, 'pause-times',
			(objs: Array<Database.ArrayResults>) => {
				if (!xp_utils.deepEquals (this.state.selectionNames, selectionNames)) {
					return;
				}

				objs.sort ((a: Database.ArrayResults, b: Database.ArrayResults) => {
					var aDate = a.runSet.commit.get ('commitDate');
					var bDate = b.runSet.commit.get ('commitDate');
					if (aDate.getTime () !== bDate.getTime ())
						return aDate - bDate;
					return a.runSet.get ('startedAt') - b.runSet.get ('startedAt');
				});

				const stateChange = conc ? { sortedResultsConc: objs } : { sortedResultsSeq: objs };
				this.setState (stateChange as any);
			}, (error: Object) => {
				alert ("error loading summaries: " + error.toString ());
			});
	}

	private onPercentileChange (e: React.FormEvent) : void {
		const percentile = parseFloat (e.target ['value']);
		this.setState ({ percentile: percentile } as any);
		this.props.onChange (this.state.selectionNames, percentile);
	}

	private benchmarkValueName (benchmark: string) : string {
		return benchmark;
	}

	private onBenchmarkChange (e: React.FormEvent) : void {
		const benchmark: string = e.target ['value'];
		const newSelectionNames = xp_utils.shallowClone (this.state.selectionNames);
		newSelectionNames.benchmark = benchmark;
		this.setState ({
			selectionNames: newSelectionNames,
			sortedResultsConc: [],
			sortedResultsSeq: []
		} as any);
		this.props.onChange (newSelectionNames, this.state.percentile);
		this.fetchResults (newSelectionNames, true);
		this.fetchResults (newSelectionNames, false);
	}

	public render () : JSX.Element {
		let benchmarkSelect: JSX.Element;
		if (this.state.benchmarks !== undefined) {
			const selectedBenchmarkValue = this.benchmarkValueName (this.state.selectionNames.benchmark);
			const benchmarkOptions = this.state.benchmarks.map (
				(benchmark: string) => {
					const value = this.benchmarkValueName (benchmark);
					return <option
						value={value}
						key={value}>
						{benchmark}
					</option>;
				});
			benchmarkSelect = <select
					size={6}
					value={selectedBenchmarkValue}
					onChange={(e: React.FormEvent) => this.onBenchmarkChange (e)}>
					{benchmarkOptions}
				</select>;
		} else {
			benchmarkSelect = <div className="diagnostic">Loading&hellip;</div>;
		}

		return <div className="TimelinePage">
			<xp_common.Navigation
				currentPage="pauseTimes" />
			<article>
				<div className="outer">
					<div className="inner">
						<div className="PauseTimeSelector">
						<label>Benchmark</label>
						{benchmarkSelect}
						<label>Percentile</label>
						<input
							type="range"
							onInput={(e: React.FormEvent) => this.onPercentileChange (e)}
							min={0}
							max={1}
							step={0.01}
							defaultValue={this.state.percentile.toString ()} />
						{Math.round (this.state.percentile * 100).toString () + "%"}
						</div>
					</div>
				</div>
				<PauseTimesChart
					graphName="pauseTimesChart"
					percentile={this.state.percentile}
					percentileRange={0.1}
					zoomInterval={undefined}
					runSetSelected={undefined}
					sortedResults={ { conc: this.state.sortedResultsConc, seq: this.state.sortedResultsSeq } } />
			</article>
		</div>;
	}
}

function calcPercentiles (results: Array<Array<number>>, percentile: number, range: number) : [number, number, number] {
	if (results.length === 0) {
		return undefined;
	}

	const delta = range / 2;
	const lowPercentile = Math.max (0, percentile - delta);
	const highPercentile = Math.min (1, percentile + delta);
	const allPauses: Array<number> = Array.prototype.concat.apply ([], results);
	const longPauses = allPauses.filter ((l: number) => l > 10);
	longPauses.sort ((a: number, b: number) => a - b);
	const lowValue = longPauses [Math.min (longPauses.length - 1, Math.floor (longPauses.length * lowPercentile))];
	const middleValue = longPauses [Math.min (longPauses.length - 1, Math.floor (longPauses.length * percentile))];
	const highValue = longPauses [Math.min (longPauses.length - 1, Math.floor (longPauses.length * highPercentile))];
	const shortest = longPauses [0];
	const longest = longPauses [longPauses.length - 1];
	return [shortest, lowValue, middleValue, highValue, longest];
}

interface BothSortedResults {
	conc: Array<Database.ArrayResults>;
	seq: Array<Database.ArrayResults>;
}

interface PauseTimesChartProps extends xp_charts.TimelineChartProps {
	sortedResults: BothSortedResults;
	percentile: number;
	percentileRange: number;
};

class PauseTimesChart extends xp_charts.TimelineChart<PauseTimesChartProps> {
	public valueAxisTitle () : string {
		return "Pause times in ms";
	}

	/*
	public logarithmic () : boolean {
		return true;
	}
	*/

	public timelineParameters () : Array<xp_charts.TimelineParameters> {
		return [
			{
				lowName: 'lowConc',
				midName: 'midConc',
				highName: 'highConc',
				lowBalloonName: 'lowName',
				midBalloonName: 'tooltipConc',
				highBalloonName: 'highName',
				color: xp_common.xamarinColors.blue [2],
				title: "Concurrent"
			},
			{
				lowName: 'lowSeq',
				midName: 'midSeq',
				highName: 'highSeq',
				lowBalloonName: 'lowSeqName',
				midBalloonName: 'tooltipSeq',
				highBalloonName: 'highSeqName',
				color: xp_common.xamarinColors.green [2],
				title: "Non-Concurrent"
			}
		];
	}

	public computeTable (nextProps: PauseTimesChartProps) : Array<Object> {
		const seqCommitIndexes: { [id: string]: number } = {};
		for (let i = 0; i < nextProps.sortedResults.seq.length; ++i) {
			seqCommitIndexes [nextProps.sortedResults.seq [i].runSet.commit.get ('hash')] = i;
		}

		const results = nextProps.sortedResults.conc;
		const table = [];

		for (let j = 0; j < results.length; ++j) {
			const runSet = results [j].runSet;
			const commitHash = runSet.commit.get ('hash');
			if (!(commitHash in seqCommitIndexes)) {
				continue;
			}

			const seqResults = nextProps.sortedResults.seq [seqCommitIndexes [commitHash]];
			const concPercentiles = calcPercentiles (results [j].resultArrays, nextProps.percentile, nextProps.percentileRange);
			const seqPercentiles = calcPercentiles (seqResults.resultArrays, nextProps.percentile, nextProps.percentileRange);
			const tooltip = xp_charts.tooltipForRunSet (runSet, false);

			table.push ({
				dataItem: runSet,
				lowConc: concPercentiles [1],
				midConc: concPercentiles [2],
				highConc: concPercentiles [3],
				tooltipConc: tooltip + "\n" + concPercentiles [2].toString () + "ms",
				lowSeq: seqPercentiles [1],
				midSeq: seqPercentiles [2],
				highSeq: seqPercentiles [3],
				tooltipSeq: tooltip + "\n" + seqPercentiles [2].toString () + "ms",
			});
		}

		return table;
	}
}

function start (params: Object) : void {
	var benchmark = params ['benchmark'];
	const percentile = params ['percentile'];
	var controller = new Controller (benchmark, percentile);
	controller.loadAsync ();
}

xp_common.parseLocationHashForDict (['benchmark', 'percentile'], start);
