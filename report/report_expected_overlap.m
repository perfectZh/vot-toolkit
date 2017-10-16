function [document, expected_overlap_scores] = report_expected_overlap(context, trackers, sequences, experiments, varargin)
% report_ranking Generate a report based on expected overlap
%
% Performs expected overlap analysis and generates a report based on the results.
%
% Input:
% - context (structure): Report context structure.
% - trackers (cell): An array of tracker structures.
% - sequences (cell): An array of sequence structures.
% - experiments (cell): An array of experiment structures.
% - varargin[UsePractical] (boolean): Use practical difference.
% - varargin[UseTags] (boolean): Rank according to tags (otherwise rank according to sequences).
% - varargin[HideLegend] (boolean): Hide legend in plots.
% - varargin[RangeThreshold] (double): Threshold used for range estimation.
%
% Output:
% - document (structure): Resulting document structure.
% - expected_overlap_scores (matrix): Averaged scores for entire set.

usetags = get_global_variable('report_tags', true);
usepractical = false;
hidelegend = get_global_variable('report_legend_hide', false);
range_threshold = 0.5;

for i = 1:2:length(varargin)
    switch lower(varargin{i})
        case 'usepractical'
            usepractical = varargin{i+1};
        case 'usetags'
            usetags = varargin{i+1};
        case 'hidelegend'
            hidelegend = varargin{i+1};
        case 'rangethreshold'
            range_threshold = varargin{i+1};
        otherwise
            error(['Unknown switch ', varargin{i}, '!']);
    end
end

document = create_document(context, 'expected_overlap', 'title', 'Expected overlap analysis');

% TODO: This may no longer be necessary?
% Filter out all experiments that are not of type "supervised"
experiments = experiments(cellfun(@(e) any(strcmp(e.type, {'supervised', 'realtime'})), experiments, 'UniformOutput', true));

trackers_hash = md5hash(strjoin((cellfun(@(x) x.identifier, trackers, 'UniformOutput', false)), '-'), 'Char', 'hex');
parameters_hash = md5hash(sprintf('%d-%d', usetags, usepractical));
sequences_hash = md5hash(strjoin((cellfun(@(x) x.name, sequences, 'UniformOutput', false)), '-'), 'Char', 'hex');

expected_overlap_scores = zeros(numel(experiments), numel(trackers), 1);

tracker_labels = cellfun(@(x) iff(isfield(x.metadata, 'verified') && x.metadata.verified, [x.label, '*'], x.label), trackers, 'UniformOutput', 0);

for e = 1:length(experiments)

    cache_identifier_curves = sprintf('expected_overlap_%s_%s_%s_%s', experiments{e}.name, ...
        trackers_hash, sequences_hash, parameters_hash);

    cache_identifier_scores = sprintf('average_expected_overlap_%s_%s_%s_%s', experiments{e}.name, ...
        trackers_hash, sequences_hash, parameters_hash);

    if usetags
        tags = cat(2, {'all'}, experiments{e}.tags);
    else
        tags = {'all'};
    end;

    result_curves = report_cache(context, cache_identifier_curves, ...
        @analyze_expected_overlap, experiments{e}, trackers, ...
        sequences, 'Tags', tags);

    result_scores = report_cache(context, cache_identifier_scores, ...
        @analyze_average_expected_overlap, experiments{e}, trackers, ...
        sequences, 'Tags', tags);

    document.section('Experiment %s', experiments{e}.name);

    for p = 1:numel(tags)

        valid =  cellfun(@(x) numel(x) > 0, result_curves.curves, 'UniformOutput', true)';

        if p == 1
            plot_title = sprintf('Expected overlap curves for %s', experiments{e}.name);
            plot_id = sprintf('expected_overlap_curves_%s', experiments{e}.name);
        else
            plot_title = sprintf('Expected overlap curves for %s (%s)', experiments{e}.name, tags{p});
            plot_id = sprintf('expected_overlap_curves_%s_%s', experiments{e}.name, tags{p});
            document.subsection('Tag %s', tags{p});
        end;

        handle = generate_plot('Visible', false, ...
            'Title', plot_title, 'Width', 8);

        hold on;

        plot([result_scores.peak, result_scores.peak], [1, 0], '--', 'Color', [0.6, 0.6, 0.6]);
        plot([result_scores.low, result_scores.low], [1, 0], ':', 'Color', [0.6, 0.6, 0.6]);
        plot([result_scores.high, result_scores.high], [1, 0], ':', 'Color', [0.6, 0.6, 0.6]);

        phandles = zeros(numel(trackers), 1);
        for t = find(valid)
            phandles(t) = plot(result_curves.lengths, result_curves.curves{t}(:, p), 'Color', trackers{t}.style.color);
        end;

        if ~hidelegend
            legend(phandles(valid), cellfun(@(x) x.label, trackers(valid), 'UniformOutput', false), 'Location', 'NorthWestOutside', 'interpreter', 'none');
        end;

        xlabel('Sequence length');
        ylabel('Expected overlap');
        xlim([1, max(result_curves.lengths(:))]);
        ylim([0, 1]);

        hold off;

        document.figure(handle, plot_id, plot_title);

        close(handle);

        plot_title = sprintf('Expected overlap scores for %s', experiments{e}.name);
        plot_id = sprintf('expected_overlaps_%s_%s', experiments{e}.name, tags{p});

        handle = generate_plot('Visible', false, ...
            'Title', plot_title, 'Grid', false);

        hold on;

        [ordered_scores, order] = sort(result_scores.scores(:, p), 'descend');

        phandles = zeros(numel(trackers), 1);
        for t = 1:numel(order)
            tracker = trackers{order(t)};
            plot([t, t], [0, ordered_scores(t)], ':', 'Color', [0.8, 0.8, 0.8]);
            phandles(t) = plot(t, ordered_scores(t), tracker.style.symbol, 'Color', tracker.style.color, 'MarkerSize', 10, 'LineWidth', tracker.style.width);
        end;

        if ~hidelegend
            legend(phandles, cellfun(@(x) x.label, trackers(order), 'UniformOutput', false), 'Location', 'NorthWestOutside', 'interpreter', 'none');
        end;

        xlabel('Order');
        ylabel('Average expected overlap');
        xlim([0.9, numel(trackers) + 0.1]);
        set(gca, 'XTick', 1:max(1, ceil(log(numel(trackers)))):numel(trackers));
        set(gca, 'XDir', 'Reverse');
        ylim([0, 1]);

        hold off;

        document.figure(handle, plot_id, plot_title);

        close(handle);
    end;

    document.subsection('Overview');
    document.text('Scores calculated as an average over interval %d to %d', result_scores.low, result_scores.high);

    if usetags && numel(tags) > 1

        h = generate_ordering_plot(trackers, result_scores.scores(:, 2:end)' , tags(2:end), ...
            'flip', false, 'legend', ~hidelegend, 'scope', [0, 1]);
            document.figure(h, sprintf('ordering_expected_overlap_%s', experiments{e}.name), ...
            'Ordering plot for expected overlap');

        close(h);

    end

	[~, order] = sort(result_scores.scores(:, 1), 'descend');

    expected_overlap_scores(e, :, 1) = result_scores.scores(:, 1);

	tabledata = num2cell(result_scores.scores);
	tabledata = highlight_best_rows(tabledata, repmat({'descending'}, 1, numel(tags)));

	document.table(tabledata(order, :), 'columnLabels', tags, 'rowLabels', tracker_labels(order));

end;

document.write();

end

% function draw_interval(x, y, low, high, varargin)
%     plot([x - 0.1, x + 0.1], [y, y] - low, varargin{:});
%     plot([x - 0.1, x + 0.1], [y, y] + high, varargin{:});
%     plot([x, x], [y - low, y + high], varargin{:});
% end

