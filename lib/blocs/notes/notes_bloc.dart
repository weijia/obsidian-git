import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/note.dart';
import '../../models/folder.dart';
import '../../services/note_storage_service.dart';
import '../../services/git_service.dart';

// Events
abstract class NotesEvent extends Equatable {
  const NotesEvent();

  @override
  List<Object?> get props => [];
}

class LoadNotes extends NotesEvent {
  final String? folderPath;
  const LoadNotes({this.folderPath});

  @override
  List<Object?> get props => [folderPath];
}

class CreateNote extends NotesEvent {
  final String title;
  final String? folderPath;
  final String content;
  const CreateNote({
    required this.title,
    this.folderPath,
    this.content = '',
  });

  @override
  List<Object?> get props => [title, folderPath, content];
}

class SelectNote extends NotesEvent {
  final Note note;
  const SelectNote(this.note);

  @override
  List<Object?> get props => [note];
}

class UpdateNote extends NotesEvent {
  final Note note;
  const UpdateNote(this.note);

  @override
  List<Object?> get props => [note];
}

class DeleteNote extends NotesEvent {
  final String filePath;
  const DeleteNote(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

class SearchNotes extends NotesEvent {
  final String query;
  const SearchNotes(this.query);

  @override
  List<Object?> get props => [query];
}

class SyncWithGit extends NotesEvent {
  const SyncWithGit();
}

// States
abstract class NotesState extends Equatable {
  const NotesState();

  @override
  List<Object?> get props => [];
}

class NotesInitial extends NotesState {}

class NotesLoading extends NotesState {}

class NotesLoaded extends NotesState {
  final List<Note> notes;
  final List<Folder> folders;
  final Note? selectedNote;
  final String? currentFolderPath;
  final String? searchQuery;
  final bool isSyncing;
  final String? syncError;

  const NotesLoaded({
    required this.notes,
    required this.folders,
    this.selectedNote,
    this.currentFolderPath,
    this.searchQuery,
    this.isSyncing = false,
    this.syncError,
  });

  NotesLoaded copyWith({
    List<Note>? notes,
    List<Folder>? folders,
    Note? selectedNote,
    String? currentFolderPath,
    String? searchQuery,
    bool? isSyncing,
    String? syncError,
    bool clearSelectedNote = false,
    bool clearSyncError = false,
  }) {
    return NotesLoaded(
      notes: notes ?? this.notes,
      folders: folders ?? this.folders,
      selectedNote: clearSelectedNote ? null : (selectedNote ?? this.selectedNote),
      currentFolderPath: currentFolderPath ?? this.currentFolderPath,
      searchQuery: searchQuery ?? this.searchQuery,
      isSyncing: isSyncing ?? this.isSyncing,
      syncError: clearSyncError ? null : (syncError ?? this.syncError),
    );
  }

  @override
  List<Object?> get props => [
        notes,
        folders,
        selectedNote,
        currentFolderPath,
        searchQuery,
        isSyncing,
        syncError,
      ];
}

class NotesError extends NotesState {
  final String message;
  const NotesError(this.message);

  @override
  List<Object?> get props => [message];
}

// Bloc
class NotesBloc extends Bloc<NotesEvent, NotesState> {
  final NoteStorageService _storageService;
  final GitService _gitService;

  NotesBloc({
    required NoteStorageService storageService,
    required GitService gitService,
  })  : _storageService = storageService,
        _gitService = gitService,
        super(NotesInitial()) {
    on<LoadNotes>(_onLoadNotes);
    on<CreateNote>(_onCreateNote);
    on<SelectNote>(_onSelectNote);
    on<UpdateNote>(_onUpdateNote);
    on<DeleteNote>(_onDeleteNote);
    on<SearchNotes>(_onSearchNotes);
    on<SyncWithGit>(_onSyncWithGit);
  }

  Future<void> _onLoadNotes(
    LoadNotes event,
    Emitter<NotesState> emit,
  ) async {
    emit(NotesLoading());
    try {
      final notes = event.folderPath != null
          ? await _storageService.getNotesInFolder(event.folderPath!)
          : await _storageService.getAllNotes();
      final folders = await _storageService.getAllFolders();
      emit(NotesLoaded(
        notes: notes,
        folders: folders,
        currentFolderPath: event.folderPath,
      ));
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  Future<void> _onCreateNote(
    CreateNote event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    try {
      final note = await _storageService.createNote(
        title: event.title,
        folderPath: event.folderPath,
        content: event.content,
      );

      final updatedNotes = [...currentState.notes, note];
      emit(currentState.copyWith(
        notes: updatedNotes,
        selectedNote: note,
      ));
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  Future<void> _onSelectNote(
    SelectNote event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    // 加载完整笔记内容
    final note = await _storageService.getNote(event.note.filePath);
    emit(currentState.copyWith(selectedNote: note ?? event.note));
  }

  Future<void> _onUpdateNote(
    UpdateNote event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    try {
      await _storageService.saveNote(event.note);

      final updatedNotes = currentState.notes.map((n) {
        return n.filePath == event.note.filePath ? event.note : n;
      }).toList();

      emit(currentState.copyWith(
        notes: updatedNotes,
        selectedNote: event.note,
      ));
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  Future<void> _onDeleteNote(
    DeleteNote event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    try {
      await _storageService.deleteNote(event.filePath);

      final updatedNotes = currentState.notes
          .where((n) => n.filePath != event.filePath)
          .toList();

      emit(currentState.copyWith(
        notes: updatedNotes,
        clearSelectedNote: currentState.selectedNote?.filePath == event.filePath,
      ));
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  Future<void> _onSearchNotes(
    SearchNotes event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    try {
      final notes = event.query.isEmpty
          ? await _storageService.getAllNotes()
          : await _storageService.searchNotes(event.query);

      emit(currentState.copyWith(
        notes: notes,
        searchQuery: event.query.isEmpty ? null : event.query,
      ));
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  Future<void> _onSyncWithGit(
    SyncWithGit event,
    Emitter<NotesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! NotesLoaded) return;

    emit(currentState.copyWith(isSyncing: true, clearSyncError: true));

    try {
      final result = await _gitService.sync();

      if (result.success) {
        // 重新加载笔记
        final notes = await _storageService.getAllNotes();
        emit(currentState.copyWith(
          notes: notes,
          isSyncing: false,
        ));
      } else {
        emit(currentState.copyWith(
          isSyncing: false,
          syncError: result.error,
        ));
      }
    } catch (e) {
      emit(currentState.copyWith(
        isSyncing: false,
        syncError: e.toString(),
      ));
    }
  }
}
