-module(test).
-include_lib("wx/include/wx.hrl").

-export([min_max/1]).
-export([back_forth/1, forth/0]).
-export([proc_ring/1, ring_proc/1]).
-export([proc_star/2, send_message/2, star_proc/0]).
-export([start/1, slave/1, master/1, to_slave/2]).
-export([robust/0, create_win/2, loop/3, t/0]).

% ---------------- Exercises ----------------
% http://www.erlang.org/course/exercises.html

% Recusive 3 
min_max([H|T]) ->
	min_max_help(T, H, H);

min_max([]) -> false.

min_max_help([H|T], Min, Max) when H < Min ->
	min_max_help(T, H, Max);

min_max_help([H|T], Min, Max) when H > Max ->
	min_max_help(T, Min, H);

min_max_help([], Min, Max) -> {Min, Max}.

% Concurrency 1
back_forth(N) ->
	back(N, spawn(test, forth, [])).
	
back(N, Pid) when N > 0 ->
	Pid ! {self(), hello},
	receive
		{Pid, Msg} ->
			io:format("P1 ~w~n",[Msg]),
			back(N-1, Pid)
	end;

back(0, Pid) -> 
	Pid ! stop.

forth() ->
	receive
		{From, Msg} ->
			From ! {self(), Msg},
			forth();
		stop ->
			true
	end.

% Concurrency 2
proc_ring(N) ->
	Pid = spawn(test, new_ring_proc, [N]),
	Pid ! new,
	receive
		done ->
			io:fwrite("Done!\n")
	end.

ring_proc(N) when N > 0 ->
	receive
		new ->
			io:fwrite("New process\n"),
			Pid = spawn(test, ring_proc, [N-1]),
			Pid ! new
	end;

ring_proc(0) -> 
	origin ! done.

% Concurrency 3
proc_star(N, M) when N > 0 ->
	Pid = spawn(test, star_proc, []),
	send_message(Pid, M),
	proc_star(N-1, M);

proc_star(0, _) -> false.

send_message(Pid, M) when M > 0 -> 
	Pid ! message,
	send_message(Pid, M-1);

send_message(Pid, 0) -> Pid ! stop.

star_proc() ->
	receive
		message ->
			io:fwrite("Message received\n"),
			star_proc();
		stop ->
			io:fwrite("Messages done\n")
	end.

% Master/Slave
start(N) when N > 0 ->
	Pid = spawn_link(test, master, [N]),
	register(master, Pid).

master(0) -> 
	receive
		{N, Msg} ->
			get(N) ! Msg,
			master(0);
		{'EXIT', Slave, _} ->
			N = get(Slave),
			io:fwrite("Master restarting dead slave ~w~n", [N]),
			erase(N),
			erase(Slave),
			Pid = spawn_link(test, slave, [N]),
			put(N, Pid),
			put(Pid, N),
			master(0)
	end;

master(N) ->
	io:fwrite("Master ~w~n", [N]),
	process_flag(trap_exit, true),
	Pid = spawn_link(test, slave, [N]),
	put(N, Pid),
	put(Pid, N),
	master(N-1).

slave(N) ->
	receive
		die ->
			exit(dead);
		Msg -> 
			io:fwrite("Slave ~w got message ~w~n", [N, Msg]),
			slave(N)		
	end.

to_slave(N, Msg) ->
	master ! {N, Msg}.

% GUI/Robustness

robust() ->
	create_win({500, 50}, self()).

% Finding a tutorial using decent wx took a lot of time. I used http://erlangcentral.org/frame/?href=http%3A%2F%2Fwxerlang.dougedmunds.com#.VA4dq0hQaJM
create_win(Pos, Parent) ->
	{X, Y} = Pos,
	process_flag(trap_exit, true),
	Wx = wx:new(),
	Frame = wxFrame:new(Wx, -1, "Robustness", [{size, {250, 80}}, {pos, {X, Y}}]),
	Panel = wxPanel:new(Frame),
	A = wxButton:new(Panel, ?wxID_EXIT, [{label, "Quit"}]),
	B = wxButton:new(Panel, 1, [{label, "Spawn"}]),
	C = wxButton:new(Panel, 2, [{label, "Error"}]),
	% A sizer is like a linear layout in Android. It can be vertical or horizontal
	Sizer = wxBoxSizer:new(?wxHORIZONTAL),
	wxSizer:add(Sizer, A, []),
	wxSizer:add(Sizer, B, []),
	wxSizer:add(Sizer, C, []),
	wxPanel:setSizer(Panel, Sizer),
	wxFrame:show(Frame),
	wxFrame:connect(Frame, close_window),
	wxPanel:connect(Panel, command_button_clicked),
	% Functions that receive event messages have to be run in the foreground
	loop(Frame, Pos, Parent).
	% spawn_link(test, t, []).
	
loop(Frame, Pos, Parent) ->
	{X, Y} = Pos,
	receive
		% These messages are macros predefined in wx.hrl
		#wx{event = #wxClose{}} ->
			io:fwrite("~p Closing window via X button.~n", [self()]),
			wxWindow:destroy(Frame),
			exit(normal);
		#wx{id = ?wxID_EXIT, event=#wxCommand{type = command_button_clicked} } ->
			io:fwrite("~p Closing window via quit button.~n", [self()]),
			wxWindow:destroy(Frame),
			exit(normal);
		#wx{id = 1, event=#wxCommand{type = command_button_clicked}} ->
			io:fwrite("Spawning window.~n"),
			spawn_link(test, create_win, [{X + 50, Y + 50}, self()]);
		#wx{id = 2, event=#wxCommand{type = command_button_clicked}} ->
			io:fwrite("Exiting.~n"),
			wxWindow:destroy(Frame),
			exit(bad);
		{'EXIT', Pid, _} ->
			if
				Parent == Pid ->
					io:fwrite("Exiting.~n"),
					wxWindow:destroy(Frame),
					exit(bad);
				% true is an else case
				true ->
					io:fwrite("Spawning replacement window.~n"),
					spawn_link(test, create_win, [{X + 50, Y + 50}, self()])
			end,
			io:fwrite("Received exit trap.~n"),
			ok
	end,
	loop(Frame, Pos, Parent).

% Test event message receiver
t() -> 
	receive
		#wx{event = #wxClose{}} ->
			io:fwrite("Received close button press~n");
		#wx{id = ?wxID_EXIT, event=#wxCommand{type = command_button_clicked} } ->
			io:fwrite("Received close button press 1~n");
		#wx{id = 1, event=#wxCommand{type = command_button_clicked}} ->
			io:fwrite("Received spawn press~n");
		#wx{id = 2, event=#wxCommand{type = command_button_clicked}} ->
			io:fwrite("Received error press~n")
		after 0 -> 
		 	empty
	end,
	t().
